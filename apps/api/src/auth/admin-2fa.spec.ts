import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
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
import { fakeGoogleIdTokens } from "./test-google-id-token.js";

/**
 * ADR-022 §5's own named-missing test: create a user, promote to admin,
 * confirm `AdminGuard` blocks with `ADMIN_2FA_REQUIRED` while
 * `twoFactorEnabled` is false, then confirm it allows access once 2FA is
 * actually verified. Runs against the real dev Postgres (`two_factor`
 * table + `user.two_factor_enabled` column, `packages/db/drizzle/0003_
 * little_blink.sql`) and Redis -- no mocking of Better Auth itself.
 */
/** Documentation range (RFC 5737), distinct from the 127.0.0.1 fallback. */
const CLIENT_IP = "198.51.100.22";
const JSON_HEADERS = { "content-type": "application/json", "x-forwarded-for": CLIENT_IP };
/** One client IP per strong-session test, so none eats another's rate-limit budget. */
const STRONG_SESSION_IPS = [
  "198.51.100.23",
  "198.51.100.24",
  "198.51.100.25",
  "198.51.100.26",
  "198.51.100.27",
] as const;
const PASSWORD = "correcthorsebatterystaple123";

describe("AdminGuard + twoFactor plugin lifecycle (ADR-022 §5)", () => {
  let testApp: TestAuthApp;
  let dbPool: ReturnType<typeof createDb>["pool"];

  beforeAll(async () => {
    await ensureTestDatabaseMigrated();
    // Its own client IP: `auth-flows.spec.ts` runs in parallel and counts
    // on the 127.0.0.1 rate-limit budget. Cleared so back-to-back runs
    // within the rate-limit windows start from zero.
    for (const ip of [CLIENT_IP, ...STRONG_SESSION_IPS]) {
      await clearRateLimitCounters(ip);
    }
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

  function post(path: string, body: unknown, ip: string, cookie?: string): Promise<Response> {
    return fetch(`${testApp.baseUrl}/api/auth${path}`, {
      method: "POST",
      headers: { "content-type": "application/json", "x-forwarded-for": ip, ...(cookie ? { cookie } : {}) },
      body: JSON.stringify(body),
    });
  }

  /** `name=value` of the response cookie whose name contains `fragment`. */
  function cookieNamed(response: Response, fragment: string): string | undefined {
    return response.headers
      .getSetCookie()
      .map((header) => header.split(";")[0] ?? "")
      .find((pair) => pair.split("=")[0]?.includes(fragment) && !pair.endsWith("="));
  }

  /**
   * Signs up an account, promotes it to admin and, with `twoFactor`,
   * enables and verifies TOTP 2FA (the backoffice enrollment flow).
   */
  async function createAdmin(
    label: string,
    ip: string,
    { twoFactor }: { twoFactor: boolean },
  ): Promise<{ email: string; userId: string; totpSecret: string | null }> {
    const email = uniqueEmail(label);
    const signUp = await post("/sign-up/email", { email, password: PASSWORD, name: label }, ip);
    expect(signUp.status).toBe(200);
    const { user } = (await signUp.json()) as { user: { id: string } };
    const context = await testApp.app.get(AUTH_INSTANCE).$context;
    await context.internalAdapter.updateUserByEmail(email, { role: "admin" });
    if (!twoFactor) return { email, userId: user.id, totpSecret: null };

    const signIn = await post("/sign-in/email", { email, password: PASSWORD }, ip);
    const cookie = cookieNamed(signIn, "session_token");
    const enable = await post("/two-factor/enable", { password: PASSWORD }, ip, cookie);
    expect(enable.status).toBe(200);
    const { totpURI } = (await enable.json()) as { totpURI: string };
    const totpSecret = new URL(totpURI).searchParams.get("secret");
    const verify = await post("/two-factor/verify-totp", { code: await computeTotpCode(totpSecret!) }, ip, cookie);
    expect(verify.status).toBe(200);
    return { email, userId: user.id, totpSecret };
  }

  /** Signs in with a Sign-in code (ADR-035 §2) and returns the bearer token. */
  async function signInWithCode(email: string, ip: string): Promise<string> {
    const spy = vi.spyOn(testApp.notificationsService, "sendAuthEmail");
    spy.mockClear();
    const send = await post("/email-otp/send-verification-otp", { email, type: "sign-in" }, ip);
    expect(send.status).toBe(200);
    const html = spy.mock.calls.find((call) => call[0].to === email)?.[0].html ?? "";
    const otp = /\b\d{6}\b/.exec(html.replace(/<[^>]*>/g, " "))?.[0];
    const signIn = await post("/sign-in/email-otp", { email, otp }, ip);
    expect(signIn.status).toBe(200);
    const { token } = (await signIn.json()) as { token: string };
    return token;
  }

  async function getAs(path: string, auth: { cookie: string } | { bearer: string }): Promise<Response> {
    const headers = "cookie" in auth ? { cookie: auth.cookie } : { authorization: `Bearer ${auth.bearer}` };
    return fetch(`${testApp.baseUrl}${path}`, { headers });
  }

  it("blocks a freshly-promoted admin (ADMIN_2FA_REQUIRED), then allows access once TOTP 2FA is verified", async () => {
    const email = uniqueEmail("admin-2fa-lifecycle");
    const password = "correcthorsebatterystaple123";

    // 1. Sign up an ordinary user.
    const signUpResponse = await fetch(`${testApp.baseUrl}/api/auth/sign-up/email`, {
      method: "POST",
      headers: JSON_HEADERS,
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
      headers: JSON_HEADERS,
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
      headers: { ...JSON_HEADERS, cookie: cookie! },
      body: JSON.stringify({ password }),
    });
    expect(enableResponse.status).toBe(200);
    const enableBody = (await enableResponse.json()) as { totpURI: string };
    const secretMatch = /secret=([^&]+)/.exec(enableBody.totpURI);
    const secret = secretMatch?.[1] ? decodeURIComponent(secretMatch[1]) : null;
    expect(secret).toBeTruthy();
    // The authenticator app shows the Nervo brand (ADR-032 §1).
    expect(new URL(enableBody.totpURI).searchParams.get("issuer")).toBe("Nervo");

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
      headers: { ...JSON_HEADERS, cookie: cookie! },
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
      headers: JSON_HEADERS,
      body: JSON.stringify({ email, password, name: "Non Admin" }),
    });
    const signInResponse = await fetch(`${testApp.baseUrl}/api/auth/sign-in/email`, {
      method: "POST",
      headers: JSON_HEADERS,
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

  describe("strong session (ADR-035 §3)", () => {
    it("lets a 2FA admin who signs in with password + TOTP reach /v1/admin", async () => {
      const ip = STRONG_SESSION_IPS[0];
      const admin = await createAdmin("admin-password-2fa", ip, { twoFactor: true });

      const signIn = await post("/sign-in/email", { email: admin.email, password: PASSWORD }, ip);
      expect(((await signIn.json()) as { twoFactorRedirect?: boolean }).twoFactorRedirect).toBe(true);
      const twoFactorCookie = cookieNamed(signIn, "two_factor");
      expect(twoFactorCookie).toBeTruthy();

      const verify = await post(
        "/two-factor/verify-totp",
        { code: await computeTotpCode(admin.totpSecret!) },
        ip,
        twoFactorCookie,
      );
      expect(verify.status).toBe(200);
      const sessionCookie = cookieNamed(verify, "session_token");

      const response = await getAs("/v1/admin", { cookie: sessionCookie! });
      expect(response.status).toBe(200);
    });

    it("refuses a 2FA admin's Sign-in code session with ADMIN_STRONG_SESSION_REQUIRED, which still works on app routes", async () => {
      const ip = STRONG_SESSION_IPS[1];
      const admin = await createAdmin("admin-code-session", ip, { twoFactor: true });
      const bearer = await signInWithCode(admin.email, ip);

      const adminResponse = await getAs("/v1/admin", { bearer });
      expect(adminResponse.status).toBe(403);
      const body = (await adminResponse.json()) as { error: { code: string; message: string } };
      expect(body.error.code).toBe("ADMIN_STRONG_SESSION_REQUIRED");
      expect(body.error.message).toMatch(/backoffice/i);

      const appResponse = await getAs("/v1/app-route", { bearer });
      expect(appResponse.status).toBe(200);
    });

    it("refuses a 2FA admin's Google session with ADMIN_STRONG_SESSION_REQUIRED, which still works on app routes", async () => {
      const ip = STRONG_SESSION_IPS[4];
      const admin = await createAdmin("admin-google-session", ip, { twoFactor: true });
      // A first Sign-in code proves the address, so Google can link to the account.
      await signInWithCode(admin.email, ip);
      const google = fakeGoogleIdTokens();
      let bearer: string;
      try {
        const signIn = await post(
          "/sign-in/social",
          { provider: "google", idToken: { token: google.idToken(admin.email, randomUUID()) } },
          ip,
        );
        expect(signIn.status).toBe(200);
        bearer = ((await signIn.json()) as { token: string }).token;
      } finally {
        google.restore();
      }

      const adminResponse = await getAs("/v1/admin", { bearer });
      expect(adminResponse.status).toBe(403);
      const body = (await adminResponse.json()) as { error: { code: string } };
      expect(body.error.code).toBe("ADMIN_STRONG_SESSION_REQUIRED");

      const appResponse = await getAs("/v1/app-route", { bearer });
      expect(appResponse.status).toBe(200);
    });

    it("does not let a client upgrade its own session through /update-session", async () => {
      const ip = STRONG_SESSION_IPS[1];
      const admin = await createAdmin("admin-update-session", ip, { twoFactor: true });
      const bearer = await signInWithCode(admin.email, ip);

      await fetch(`${testApp.baseUrl}/api/auth/update-session`, {
        method: "POST",
        headers: { "content-type": "application/json", "x-forwarded-for": ip, authorization: `Bearer ${bearer}` },
        body: JSON.stringify({ authMethod: "password_2fa" }),
      });

      const response = await getAs("/v1/admin", { bearer });
      expect(response.status).toBe(403);
      const body = (await response.json()) as { error: { code: string } };
      expect(body.error.code).toBe("ADMIN_STRONG_SESSION_REQUIRED");
    });

    it("asks an admin without 2FA to enable it first (ADMIN_2FA_REQUIRED), even on a weak session", async () => {
      const ip = STRONG_SESSION_IPS[2];
      const admin = await createAdmin("admin-no-2fa-code", ip, { twoFactor: false });
      const bearer = await signInWithCode(admin.email, ip);

      const response = await getAs("/v1/admin", { bearer });
      expect(response.status).toBe(403);
      const body = (await response.json()) as { error: { code: string } };
      expect(body.error.code).toBe("ADMIN_2FA_REQUIRED");
    });

    it("refuses a session without authMethod (opened before ADR-035 §3)", async () => {
      const ip = STRONG_SESSION_IPS[3];
      const admin = await createAdmin("admin-legacy-session", ip, { twoFactor: true });
      // Created outside any auth endpoint, like the sessions that existed
      // before `authMethod`: no path, so no method.
      const context = await testApp.app.get(AUTH_INSTANCE).$context;
      const legacy = await context.internalAdapter.createSession(admin.userId);

      const response = await getAs("/v1/admin", { bearer: legacy.token });
      expect(response.status).toBe(403);
      const body = (await response.json()) as { error: { code: string } };
      expect(body.error.code).toBe("ADMIN_STRONG_SESSION_REQUIRED");

      const appResponse = await getAs("/v1/app-route", { bearer: legacy.token });
      expect(appResponse.status).toBe(200);
    });
  });
});
