import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createDb } from "@repo/db";
import { AuthService } from "@repo/core/auth";
import { AUTH_INSTANCE } from "@repo/core/auth";
import {
  bootstrapTestAuthApp,
  clearRateLimitCounters,
  ensureTestDatabaseMigrated,
  TEST_DATABASE_URL,
  type TestAuthApp,
} from "./test-auth-app.js";

/**
 * ADR-022 §5's own named-missing test: create a user, promote to admin,
 * confirm `AdminGuard` blocks with `ADMIN_2FA_REQUIRED` while
 * `twoFactorEnabled` is false, then confirm it allows access once 2FA is
 * actually verified. Runs against the real dev Postgres (`two_factor`
 * table + `user.two_factor_enabled` column, `packages/db/drizzle/0003_
 * little_blink.sql`) and Redis -- no mocking of Better Auth itself.
 */
describe("AdminGuard + twoFactor plugin lifecycle (ADR-022 §5)", () => {
  let testApp: TestAuthApp;
  let dbPool: ReturnType<typeof createDb>["pool"];

  beforeAll(async () => {
    await ensureTestDatabaseMigrated();
    // This suite makes < 5 sign-up/sign-in calls total, well under either
    // `customRules` max -- but a prior spec file (or a prior full run) can
    // leave the shared IP-keyed counter close to or past that max, so it's
    // still cleared here rather than assumed clean (see `clearRateLimitCounters`'s
    // own doc comment).
    await clearRateLimitCounters();
    testApp = await bootstrapTestAuthApp({ withAdminRoute: true });
    dbPool = createDb(TEST_DATABASE_URL).pool;
  });

  afterAll(async () => {
    await testApp.app.close();
    await dbPool.end();
  });

  function uniqueEmail(label: string): string {
    return `${label}-${Date.now()}-${Math.random().toString(36).slice(2)}@example.com`;
  }

  /** RFC 4226 HOTP, matching @better-auth/utils' `otp.mjs` exactly: the
   * HMAC key is the *raw* secret, but that secret is base32-encoded before
   * being embedded in `totpURI` (its own `generateQRCode` calls
   * `base32.encode(secret, ...)`) -- so the key used here must be
   * base32-*decoded* from the URI to recover the bytes Better Auth signs
   * with server-side. Confirmed by exercising the real enable/verify round
   * trip against the dev DB before writing this test. */
  function base32Decode(input: string): Uint8Array {
    const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
    let bits = "";
    for (const char of input.toUpperCase().replace(/=+$/, "")) {
      const val = alphabet.indexOf(char);
      if (val === -1) continue;
      bits += val.toString(2).padStart(5, "0");
    }
    const bytes: number[] = [];
    for (let i = 0; i + 8 <= bits.length; i += 8) {
      bytes.push(Number.parseInt(bits.slice(i, i + 8), 2));
    }
    return Uint8Array.from(bytes);
  }

  async function computeTotpCode(secretBase32: string, digits = 6): Promise<string> {
    const keyBytes = base32Decode(secretBase32);
    const keyBuffer = new ArrayBuffer(keyBytes.byteLength);
    new Uint8Array(keyBuffer).set(keyBytes);
    const key = await crypto.subtle.importKey(
      "raw",
      keyBuffer,
      { name: "HMAC", hash: { name: "SHA-1" } },
      false,
      ["sign"],
    );
    const counter = Math.floor(Date.now() / 30_000);
    const buffer = new ArrayBuffer(8);
    new DataView(buffer).setBigUint64(0, BigInt(counter), false);
    const hmac = new Uint8Array(await crypto.subtle.sign("HMAC", key, buffer));
    const lastByte = hmac[hmac.length - 1] ?? 0;
    const offset = lastByte & 15;
    const b0 = hmac[offset] ?? 0;
    const b1 = hmac[offset + 1] ?? 0;
    const b2 = hmac[offset + 2] ?? 0;
    const b3 = hmac[offset + 3] ?? 0;
    const value = (((b0 & 127) << 24) | ((b1 & 255) << 16) | ((b2 & 255) << 8) | (b3 & 255)) % 10 ** digits;
    return value.toString().padStart(digits, "0");
  }

  it("blocks a freshly-promoted admin (ADMIN_2FA_REQUIRED), then allows access once TOTP 2FA is verified", async () => {
    const email = uniqueEmail("admin-2fa-lifecycle");
    const password = "correcthorsebatterystaple123";

    // 1. Sign up an ordinary user.
    const signUpResponse = await fetch(`${testApp.baseUrl}/api/auth/sign-up/email`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email, password, name: "Admin 2FA Lifecycle" }),
    });
    expect(signUpResponse.status).toBe(200);
    const { user } = (await signUpResponse.json()) as { user: { id: string } };

    // 2. Promote to admin the same way the real backoffice would (Better
    // Auth's own internal adapter, mirroring `AuthService.markEmailUnverified`'s
    // pattern -- system-triggered update, no admin session needed here).
    const authInstance = testApp.app.get(AUTH_INSTANCE);
    const context = await authInstance.$context;
    await context.internalAdapter.updateUserByEmail(email, { role: "admin" });

    // 3. Sign in as the now-admin user.
    const signInResponse = await fetch(`${testApp.baseUrl}/api/auth/sign-in/email`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email, password }),
    });
    expect(signInResponse.status).toBe(200);
    let cookie = signInResponse.headers.get("set-cookie")?.split(";")[0];
    expect(cookie).toBeTruthy();

    // 4. AdminGuard must block: role is admin, but twoFactorEnabled is
    // still false (ADR-022 §5's named-missing test).
    const blockedResponse = await fetch(`${testApp.baseUrl}/v1/admin`, {
      headers: { cookie: cookie! },
    });
    expect(blockedResponse.status).toBe(403);
    const blockedBody = (await blockedResponse.json()) as { error: { code: string; message: string } };
    expect(blockedBody.error.code).toBe("ADMIN_2FA_REQUIRED");

    // 5. Enable 2FA (real Better Auth flow: POST /two-factor/enable).
    const authClient = new URL(`${testApp.baseUrl}/api/auth/two-factor/enable`);
    const enableResponse = await fetch(authClient, {
      method: "POST",
      headers: { "content-type": "application/json", cookie: cookie! },
      body: JSON.stringify({ password }),
    });
    expect(enableResponse.status).toBe(200);
    const enableBody = (await enableResponse.json()) as { totpURI: string };
    const secretMatch = /secret=([^&]+)/.exec(enableBody.totpURI);
    const secret = secretMatch?.[1] ? decodeURIComponent(secretMatch[1]) : null;
    expect(secret).toBeTruthy();

    // Still blocked: `enableTwoFactor` alone doesn't flip `twoFactorEnabled`
    // -- verifying the generated code does (Better Auth's own onboarding
    // flow, confirmed against the real DB before writing this test).
    const stillBlockedResponse = await fetch(`${testApp.baseUrl}/v1/admin`, {
      headers: { cookie: cookie! },
    });
    expect(stillBlockedResponse.status).toBe(403);

    // 6. Verify the TOTP code (what a real authenticator app would submit).
    const code = await computeTotpCode(secret!);
    const verifyResponse = await fetch(`${testApp.baseUrl}/api/auth/two-factor/verify-totp`, {
      method: "POST",
      headers: { "content-type": "application/json", cookie: cookie! },
      body: JSON.stringify({ code }),
    });
    expect(verifyResponse.status).toBe(200);
    const rotatedCookie = verifyResponse.headers.get("set-cookie")?.split(";")[0];
    if (rotatedCookie) cookie = rotatedCookie;

    // 7. AdminGuard must now allow access.
    const allowedResponse = await fetch(`${testApp.baseUrl}/v1/admin`, {
      headers: { cookie: cookie! },
    });
    expect(allowedResponse.status).toBe(200);
    const allowedBody = (await allowedResponse.json()) as { status: string };
    expect(allowedBody.status).toBe("ok");

    // Sanity check on the session shape `AuthService.getSession` exposes.
    const authService = testApp.app.get(AuthService);
    const headers = new Headers({ cookie: cookie! });
    const session = await authService.getSession(headers);
    expect(session?.userId).toBe(user.id);
    expect(session?.role).toBe("admin");
    expect(session?.twoFactorEnabled).toBe(true);
  });

  it("keeps a non-admin user blocked regardless of twoFactorEnabled (role check runs first)", async () => {
    const email = uniqueEmail("non-admin-2fa");
    const password = "correcthorsebatterystaple123";

    await fetch(`${testApp.baseUrl}/api/auth/sign-up/email`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email, password, name: "Non Admin" }),
    });
    const signInResponse = await fetch(`${testApp.baseUrl}/api/auth/sign-in/email`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email, password }),
    });
    const cookie = signInResponse.headers.get("set-cookie")?.split(";")[0];

    const response = await fetch(`${testApp.baseUrl}/v1/admin`, { headers: { cookie: cookie! } });
    expect(response.status).toBe(403);
    const body = (await response.json()) as { error: { code: string } };
    // Plain `forbidden` (role check), not `ADMIN_2FA_REQUIRED` -- the
    // guard's role check must short-circuit before the 2FA check.
    expect(body.error.code).not.toBe("ADMIN_2FA_REQUIRED");
  });

  it("rejects a request with no session at all with 401, before either guard's own logic runs", async () => {
    const response = await fetch(`${testApp.baseUrl}/v1/admin`);
    expect(response.status).toBe(401);
  });
});
