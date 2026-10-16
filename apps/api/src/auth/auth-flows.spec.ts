import { eq } from "drizzle-orm";
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { createDb, schema } from "@repo/db";
import {
  bootstrapTestAuthApp,
  clearRateLimitCounters,
  ensureTestDatabaseMigrated,
  TEST_DATABASE_URL,
  type TestAuthApp,
} from "./test-auth-app.js";

/**
 * End-to-end tests against the real Better Auth mount (ADR-009 §3,
 * ADR-022): `POST /api/auth/sign-up/email` / `/sign-in/email`, outside the
 * `/v1` prefix, hit over real HTTP against a real Postgres + Redis (`docker
 * compose -f docker-compose.dev.yml up -d`, ADR-018 §8) -- rate limiting
 * and cookies are exercised for real, not mocked.
 */
describe("Better Auth email sign-up/sign-in (ADR-022)", () => {
  let testApp: TestAuthApp;
  let db: ReturnType<typeof createDb>["db"];
  let dbPool: ReturnType<typeof createDb>["pool"];

  beforeAll(async () => {
    await ensureTestDatabaseMigrated();
    const connection = createDb(TEST_DATABASE_URL);
    db = connection.db;
    dbPool = connection.pool;
  });

  afterAll(async () => {
    await dbPool.end();
  });

  function uniqueEmail(label: string): string {
    return `${label}-${Date.now()}-${Math.random().toString(36).slice(2)}@example.com`;
  }

  describe("sign-up", () => {
    beforeEach(async () => {
      await clearRateLimitCounters();
      testApp = await bootstrapTestAuthApp();
    });

    it("creates the user, a verification row, and sends the verify-email with the right idempotency key", async () => {
      const sendAuthEmailSpy = vi.spyOn(testApp.notificationsService, "sendAuthEmail");
      const email = uniqueEmail("signup");

      const response = await fetch(`${testApp.baseUrl}/api/auth/sign-up/email`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ email, password: "correcthorsebatterystaple123", name: "Test User" }),
      });

      expect(response.status).toBe(200);
      const body = (await response.json()) as { user: { id: string; email: string } };
      expect(body.user.email).toBe(email);

      // `emailVerification.sendOnSignUp: true` (create-auth-instance.ts):
      // sendAuthEmail must have been called with the documented idempotency
      // key `verify-email/${user.id}` (plan item 10 / ADR-022 §3).
      expect(sendAuthEmailSpy).toHaveBeenCalledExactlyOnceWith(
        expect.objectContaining({
          to: email,
          idempotencyKey: `verify-email/${body.user.id}`,
        }),
      );

      // "The equivalent Better Auth behavior" (plan's own hedge on a
      // `verification` DB row): confirmed by reading Better Auth's own
      // `sign-up.mjs` -- `emailVerification.sendOnSignUp` mints a signed,
      // stateless JWT-style token (`createEmailVerificationToken`), not a
      // `verification` table row (that table is used by other flows, e.g.
      // `sendResetPassword`). A `verification` row was checked directly
      // against the dev DB after a real sign-up and confirmed absent, so
      // asserting one exists would be asserting the wrong thing. The
      // equivalent, stronger check: the token embedded in the email's
      // `url` is a real, usable one -- verified by extracting it from the
      // rendered HTML and calling the real `GET /api/auth/verify-email`
      // endpoint end-to-end.
      const sentHtml = sendAuthEmailSpy.mock.calls[0]?.[0]?.html;
      // ADR-032 §2: the header wordmark loads from the backoffice that hosts it.
      expect(sentHtml).toContain('src="https://admin.test/brand/nervo-wordmark-email.png"');
      const urlMatch = /href="([^"]*\/verify-email\?[^"]+)"/.exec(sentHtml ?? "");
      expect(urlMatch).not.toBeNull();
      const verifyUrl = new URL(urlMatch?.[1]?.replace(/&amp;/g, "&") ?? "");
      const token = verifyUrl.searchParams.get("token");
      expect(token).toBeTruthy();

      const verifyResponse = await fetch(
        `${testApp.baseUrl}/api/auth/verify-email?token=${token}`,
        { redirect: "manual" },
      );
      // Better Auth's `verify-email` redirects on success when a
      // `callbackURL` is present, or returns 200 with the verified user
      // otherwise -- either way, never a 4xx for a genuinely fresh token.
      expect(verifyResponse.status).toBeLessThan(400);

      const [userRow] = await db.select().from(schema.user).where(eq(schema.user.id, body.user.id));
      expect(userRow?.emailVerified).toBe(true);

      await testApp.app.close();
    });

    it("rejects a second sign-up with the same email (no account enumeration via a distinct success path)", async () => {
      const email = uniqueEmail("dupe");
      const payload = {
        method: "POST" as const,
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ email, password: "correcthorsebatterystaple123", name: "Test User" }),
      };
      const first = await fetch(`${testApp.baseUrl}/api/auth/sign-up/email`, payload);
      expect(first.status).toBe(200);

      const second = await fetch(`${testApp.baseUrl}/api/auth/sign-up/email`, payload);
      expect(second.status).not.toBe(200);

      await testApp.app.close();
    });
  });

  describe("sign-in", () => {
    const password = "correcthorsebatterystaple123";
    let email: string;

    beforeEach(async () => {
      await clearRateLimitCounters();
      testApp = await bootstrapTestAuthApp();
      email = uniqueEmail("signin");
      const signUpResponse = await fetch(`${testApp.baseUrl}/api/auth/sign-up/email`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ email, password, name: "Sign In User" }),
      });
      expect(signUpResponse.status).toBe(200);
    });

    it("succeeds with correct credentials", async () => {
      const response = await fetch(`${testApp.baseUrl}/api/auth/sign-in/email`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ email, password }),
      });

      expect(response.status).toBe(200);
      const body = (await response.json()) as { user: { email: string } };
      expect(body.user.email).toBe(email);
      expect(response.headers.get("set-cookie")).toBeTruthy();

      await testApp.app.close();
    });

    it("fails with a generic error for a wrong password (no account enumeration)", async () => {
      const response = await fetch(`${testApp.baseUrl}/api/auth/sign-in/email`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ email, password: "definitely-the-wrong-password" }),
      });

      expect(response.status).toBe(401);
      const body = (await response.json()) as { message?: string; code?: string };
      // Same shape/status as a non-existent account below: Better Auth's
      // own behavior, asserted here so a regression (e.g. a future "no
      // such user" 404) doesn't silently reintroduce enumeration.
      expect(body.code ?? body.message).toBeTruthy();

      await testApp.app.close();
    });

    it("fails the same way for an email that was never registered", async () => {
      const response = await fetch(`${testApp.baseUrl}/api/auth/sign-in/email`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ email: uniqueEmail("never-registered"), password }),
      });

      expect(response.status).toBe(401);

      await testApp.app.close();
    });
  });

  describe("rate limiting (ADR-022 §4, real Redis secondary storage)", () => {
    it("rejects the 6th sign-in attempt within 60s (customRules max: 5)", async () => {
      await clearRateLimitCounters();
      testApp = await bootstrapTestAuthApp();
      const email = uniqueEmail("ratelimit-signin");
      await fetch(`${testApp.baseUrl}/api/auth/sign-up/email`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ email, password: "correcthorsebatterystaple123", name: "Rate Limit User" }),
      });

      const attempt = () =>
        fetch(`${testApp.baseUrl}/api/auth/sign-in/email`, {
          method: "POST",
          headers: { "content-type": "application/json" },
          // Wrong password: fails auth but still counts against the
          // rate limiter, which runs before credential checking.
          body: JSON.stringify({ email, password: "wrong-password-each-time" }),
        });

      const statuses: number[] = [];
      for (let i = 0; i < 6; i += 1) {
        // eslint-disable-next-line no-await-in-loop -- attempts must be sequential to land in the same 60s window deterministically
        const response = await attempt();
        statuses.push(response.status);
      }

      expect(statuses.slice(0, 5)).not.toContain(429);
      expect(statuses[5]).toBe(429);

      await testApp.app.close();
    });

    it("rejects the 4th sign-up attempt within 60s (customRules max: 3)", async () => {
      await clearRateLimitCounters();
      testApp = await bootstrapTestAuthApp();
      const attempt = (label: string) =>
        fetch(`${testApp.baseUrl}/api/auth/sign-up/email`, {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({
            email: uniqueEmail(label),
            password: "correcthorsebatterystaple123",
            name: "Rate Limit Signup",
          }),
        });

      const statuses: number[] = [];
      for (let i = 0; i < 4; i += 1) {
        // eslint-disable-next-line no-await-in-loop -- must be sequential, see above
        const response = await attempt(`ratelimit-signup-${i}`);
        statuses.push(response.status);
      }

      expect(statuses.slice(0, 3)).not.toContain(429);
      expect(statuses[3]).toBe(429);

      await testApp.app.close();
    });
  });
});
