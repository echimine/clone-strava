import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { createDb } from "@repo/db";
import { AUTH_INSTANCE } from "@repo/core/auth";
import {
  bootstrapTestAuthApp,
  clearRateLimitCounters,
  ensureTestDatabaseMigrated,
  TEST_DATABASE_URL,
  type TestAuthApp,
} from "../../auth/test-auth-app.js";
import { computeTotpCode } from "../../testing/totp.js";

/** Documentation range (RFC 5737): one client IP per test, each with its own rate-limit budget. */
const CLIENT_IPS = ["198.51.100.61", "198.51.100.62", "198.51.100.63", "198.51.100.64"];
const PASSWORD = "correcthorsebatterystaple123";

type Entry = {
  actor_id: string | null;
  action: string;
  target_type: string;
  target_id: string | null;
  subject_user_id: string | null;
};

/**
 * Better Auth hooks write to the Journal too (ADR-038 §3): an Administrator's 2FA changes, and
 * the `admin` role granted or removed outside the backoffice. Real Better Auth, Postgres, Redis.
 */
describe("audit entries from Better Auth hooks (integration)", () => {
  let testApp: TestAuthApp;
  let dbPool: ReturnType<typeof createDb>["pool"];
  let clientIp = "";
  let nextIp = 0;

  async function entriesAbout(userId: string): Promise<Entry[]> {
    const { rows } = await dbPool.query<Entry>(
      "select * from audit.admin_audit_entry where subject_user_id = $1 order by created_at",
      [userId],
    );
    return rows;
  }

  /** Listeners run after the response: polls until the entries are there. */
  async function eventually(userId: string, count: number): Promise<Entry[]> {
    for (let attempt = 0; attempt < 50; attempt++) {
      const entries = await entriesAbout(userId);
      if (entries.length >= count) return entries;
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
    return entriesAbout(userId);
  }

  function post(path: string, body: unknown, cookie?: string): Promise<Response> {
    return fetch(`${testApp.baseUrl}/api/auth${path}`, {
      method: "POST",
      headers: { "content-type": "application/json", "x-forwarded-for": clientIp, ...(cookie ? { cookie } : {}) },
      body: JSON.stringify(body),
    });
  }

  function sessionCookie(response: Response): string {
    const pair = response.headers
      .getSetCookie()
      .map((header) => header.split(";")[0] ?? "")
      .find((cookie) => cookie.split("=")[0]?.includes("session_token") && !cookie.endsWith("="));
    expect(pair).toBeTruthy();
    return pair!;
  }

  /** Signs up and signs in an account, optionally promoted to admin by a script (no session). */
  async function account(label: string, { admin }: { admin: boolean }) {
    const email = `${label}-${Date.now()}-${Math.random().toString(36).slice(2)}@example.com`;
    const signUp = await post("/sign-up/email", { email, password: PASSWORD, name: label });
    expect(signUp.status).toBe(200);
    const { user } = (await signUp.json()) as { user: { id: string } };
    if (admin) {
      const context = await testApp.app.get(AUTH_INSTANCE).$context;
      await context.internalAdapter.updateUserByEmail(email, { role: "admin" });
    }
    const signIn = await post("/sign-in/email", { email, password: PASSWORD });
    return { userId: user.id, cookie: sessionCookie(signIn) };
  }

  /** The backoffice enrollment: enable, then verify a first TOTP code. Returns the new cookie. */
  async function enrollTotp(cookie: string): Promise<string> {
    const enable = await post("/two-factor/enable", { password: PASSWORD }, cookie);
    expect(enable.status).toBe(200);
    const { totpURI } = (await enable.json()) as { totpURI: string };
    const secret = new URL(totpURI).searchParams.get("secret")!;
    const verify = await post("/two-factor/verify-totp", { code: await computeTotpCode(secret) }, cookie);
    expect(verify.status).toBe(200);
    return sessionCookie(verify);
  }

  beforeAll(async () => {
    await ensureTestDatabaseMigrated();
    for (const ip of CLIENT_IPS) {
      await clearRateLimitCounters(ip);
    }
    testApp = await bootstrapTestAuthApp({ withAudit: true });
    dbPool = createDb(TEST_DATABASE_URL).pool;
  });

  beforeEach(() => {
    clientIp = CLIENT_IPS[nextIp++]!;
  });

  afterAll(async () => {
    await testApp?.app.close();
    await dbPool?.end();
  });

  it("records an Administrator turning 2FA on, then off, as author and athlete concerned", async () => {
    const admin = await account("audit-2fa-admin", { admin: true });
    // A promotion by a script, outside any session, is not recorded (accepted gap, ADR-038 §3).
    expect(await entriesAbout(admin.userId)).toEqual([]);

    const strongCookie = await enrollTotp(admin.cookie);
    const disable = await post("/two-factor/disable", { password: PASSWORD }, strongCookie);
    expect(disable.status).toBe(200);

    const entries = await eventually(admin.userId, 2);
    expect(entries).toMatchObject([
      { action: "admin.two_factor.enable", actor_id: admin.userId, target_type: "user", target_id: admin.userId },
      { action: "admin.two_factor.disable", actor_id: admin.userId, target_id: admin.userId },
    ]);
  });

  it("records nothing for an athlete's own 2FA", async () => {
    const athlete = await account("audit-2fa-athlete", { admin: false });
    await enrollTotp(athlete.cookie);

    await new Promise((resolve) => setTimeout(resolve, 100));
    expect(await entriesAbout(athlete.userId)).toEqual([]);
  });

  it("records the admin role granted then removed through Better Auth's own routes", async () => {
    const admin = await account("audit-role-admin", { admin: true });
    const athlete = await account("audit-role-athlete", { admin: false });

    expect((await post("/admin/set-role", { userId: athlete.userId, role: "admin" }, admin.cookie)).status).toBe(200);
    expect((await post("/admin/set-role", { userId: athlete.userId, role: "user" }, admin.cookie)).status).toBe(200);
    // Setting the role it already has changes nothing.
    expect((await post("/admin/set-role", { userId: athlete.userId, role: "user" }, admin.cookie)).status).toBe(200);

    const entries = await eventually(athlete.userId, 2);
    await new Promise((resolve) => setTimeout(resolve, 100));
    expect(await entriesAbout(athlete.userId)).toHaveLength(2);
    expect(entries).toMatchObject([
      { action: "user.role.grant", actor_id: admin.userId, target_id: athlete.userId },
      { action: "user.role.revoke", actor_id: admin.userId, target_id: athlete.userId },
    ]);
  });

  it("leaves a role change made by the API itself to the backoffice route that records it", async () => {
    const admin = await account("audit-role-api-admin", { admin: true });
    const athlete = await account("audit-role-api-athlete", { admin: false });

    await testApp.app.get(AUTH_INSTANCE).api.setRole({
      body: { userId: athlete.userId, role: "admin" },
      headers: new Headers({ cookie: admin.cookie }),
    });

    await new Promise((resolve) => setTimeout(resolve, 100));
    expect(await entriesAbout(athlete.userId)).toEqual([]);
  });
});
