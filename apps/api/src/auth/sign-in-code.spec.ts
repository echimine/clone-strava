import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import {
  bootstrapTestAuthApp,
  ensureTestDatabaseMigrated,
  type TestAuthApp,
} from "./test-auth-app.js";

/**
 * Sign-in code (ADR-035 §2): `emailOTP` plugin over the real Better Auth
 * mount, real Postgres + Redis. The code is read back from the email the
 * fake `NotificationsService` receives, the same way a person reads it.
 *
 * The plugin rate-limits each OTP path to 3 requests / 60 s per IP, so
 * every test sends from its own random client IP.
 */
describe("Sign-in code (ADR-035 §2)", () => {
  let testApp: TestAuthApp;

  beforeAll(async () => {
    await ensureTestDatabaseMigrated();
    testApp = await bootstrapTestAuthApp();
  });

  afterAll(async () => {
    await testApp.app.close();
  });

  function uniqueEmail(label: string): string {
    return `${label}-${Date.now()}-${Math.random().toString(36).slice(2)}@example.com`;
  }

  /** A random address in 10.0.0.0/8, so no two tests share a rate-limit budget. */
  function randomIp(): string {
    const byte = () => Math.floor(Math.random() * 254) + 1;
    return `10.${byte()}.${byte()}.${byte()}`;
  }

  function post(
    app: TestAuthApp,
    path: string,
    body: unknown,
    ip: string,
  ): Promise<Response> {
    return fetch(`${app.baseUrl}/api/auth${path}`, {
      method: "POST",
      headers: { "content-type": "application/json", "x-forwarded-for": ip },
      body: JSON.stringify(body),
    });
  }

  /** Requests a code and returns the 6 digits shown in the email that was sent. */
  async function requestCode(
    app: TestAuthApp,
    email: string,
    ip: string,
  ): Promise<string> {
    const spy = vi.spyOn(app.notificationsService, "sendAuthEmail");
    spy.mockClear();
    const response = await post(
      app,
      "/email-otp/send-verification-otp",
      { email, type: "sign-in" },
      ip,
    );
    expect(response.status).toBe(200);
    const html =
      spy.mock.calls.find((call) => call[0].to === email)?.[0].html ?? "";
    const code = /\b\d{6}\b/.exec(html.replace(/<[^>]*>/g, " "))?.[0];
    expect(code).toBeDefined();
    return code ?? "";
  }

  function signInWithCode(
    app: TestAuthApp,
    body: { email: string; otp: string; name?: string },
    ip: string,
  ) {
    return post(app, "/sign-in/email-otp", body, ip);
  }

  it("creates a verified account with the given name on the first valid code, and returns a bearer token", async () => {
    const email = uniqueEmail("code-signup");
    const ip = randomIp();
    const otp = await requestCode(testApp, email, ip);

    const response = await signInWithCode(
      testApp,
      { email, otp, name: "Jeanne Martin" },
      ip,
    );

    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      user: { email: string; name: string; emailVerified: boolean };
    };
    expect(body.user).toMatchObject({
      email,
      name: "Jeanne Martin",
      emailVerified: true,
    });
    expect(response.headers.get("set-auth-token")).toBeTruthy();
  });

  it("signs an existing account in with a later code without changing its name", async () => {
    const email = uniqueEmail("code-again");
    const ip = randomIp();
    const first = await signInWithCode(
      testApp,
      {
        email,
        otp: await requestCode(testApp, email, ip),
        name: "Jeanne Martin",
      },
      ip,
    );
    const created = (await first.json()) as { user: { id: string } };

    const second = await signInWithCode(
      testApp,
      { email, otp: await requestCode(testApp, email, ip), name: "Autre Nom" },
      ip,
    );

    expect(second.status).toBe(200);
    const body = (await second.json()) as {
      user: { id: string; name: string };
    };
    expect(body.user).toMatchObject({
      id: created.user.id,
      name: "Jeanne Martin",
    });
    expect(second.headers.get("set-auth-token")).toBeTruthy();
  });

  it("lands on the same user as an existing password account with the same email", async () => {
    const email = uniqueEmail("code-existing");
    const ip = randomIp();
    const signUp = await post(
      testApp,
      "/sign-up/email",
      { email, password: "correcthorsebatterystaple123", name: "Paul Durand" },
      ip,
    );
    const existing = (await signUp.json()) as { user: { id: string } };

    const response = await signInWithCode(
      testApp,
      { email, otp: await requestCode(testApp, email, ip) },
      ip,
    );

    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      user: { id: string; name: string; emailVerified: boolean };
    };
    expect(body.user).toMatchObject({
      id: existing.user.id,
      name: "Paul Durand",
      emailVerified: true,
    });
  });

  it("refuses a wrong code", async () => {
    const email = uniqueEmail("code-wrong");
    const ip = randomIp();
    const otp = await requestCode(testApp, email, ip);

    const response = await signInWithCode(
      testApp,
      { email, otp: otp === "123456" ? "654321" : "123456" },
      ip,
    );

    expect(response.status).toBe(400);
    expect(await response.json()).toMatchObject({ code: "INVALID_OTP" });
  });

  it("refuses a code past its 5 minutes", async () => {
    const email = uniqueEmail("code-expired");
    const ip = randomIp();
    const otp = await requestCode(testApp, email, ip);

    vi.useFakeTimers({
      toFake: ["Date"],
      now: Date.now() + 5 * 60_000 + 1_000,
    });
    try {
      const response = await signInWithCode(testApp, { email, otp }, ip);

      expect(response.status).toBe(400);
      expect(await response.json()).toMatchObject({ code: "OTP_EXPIRED" });
    } finally {
      vi.useRealTimers();
    }
  });

  // Each attempt comes from another IP: the per-IP rate limit (3 / 60 s)
  // would otherwise answer the 4th request with 429 before the code check.
  it("kills the code after 3 wrong attempts, even for the right code (TOO_MANY_ATTEMPTS)", async () => {
    const email = uniqueEmail("code-attempts");
    const otp = await requestCode(testApp, email, randomIp());
    const wrong = otp === "123456" ? "654321" : "123456";

    const failures: number[] = [];
    for (let i = 0; i < 3; i += 1) {
      // eslint-disable-next-line no-await-in-loop -- attempts are counted in order
      const response = await signInWithCode(
        testApp,
        { email, otp: wrong },
        randomIp(),
      );
      failures.push(response.status);
    }
    const afterThirdFailure = await signInWithCode(
      testApp,
      { email, otp },
      randomIp(),
    );

    expect(failures).toEqual([400, 400, 400]);
    expect(afterThirdFailure.status).toBe(403);
    expect(await afterThirdFailure.json()).toMatchObject({
      code: "TOO_MANY_ATTEMPTS",
    });
  });

  it("invalidates the previous code when a new one is sent", async () => {
    const email = uniqueEmail("code-resend");
    const ip = randomIp();
    const firstCode = await requestCode(testApp, email, ip);
    const secondCode = await requestCode(testApp, email, ip);

    const withFirst = await signInWithCode(
      testApp,
      { email, otp: firstCode },
      ip,
    );
    const withSecond = await signInWithCode(
      testApp,
      { email, otp: secondCode },
      ip,
    );

    // Both codes may collide (1 in 10^6), in which case the first call signs in.
    expect(withFirst.status).toBe(firstCode === secondCode ? 200 : 400);
    expect(withSecond.status).toBe(firstCode === secondCode ? 400 : 200);
  });

  it("sends the code email once, keyed on the address and the code (ADR-023)", async () => {
    const email = uniqueEmail("code-email");
    const spy = vi.spyOn(testApp.notificationsService, "sendAuthEmail");
    spy.mockClear();

    const otp = await requestCode(testApp, email, randomIp());

    expect(spy).toHaveBeenCalledExactlyOnceWith(
      expect.objectContaining({
        to: email,
        idempotencyKey: `sign-in-code/${email}-${otp}`,
      }),
    );
  });

  describe("password sign-up closed (production rule)", () => {
    let closedApp: TestAuthApp;

    beforeAll(async () => {
      closedApp = await bootstrapTestAuthApp({ allowPasswordSignUp: false });
    });

    afterAll(async () => {
      await closedApp.app.close();
    });

    it("refuses POST /sign-up/email", async () => {
      const response = await post(
        closedApp,
        "/sign-up/email",
        {
          email: uniqueEmail("closed-signup"),
          password: "correcthorsebatterystaple123",
          name: "Refusé",
        },
        randomIp(),
      );

      expect(response.status).toBe(400);
    });

    it("still signs an existing account in with POST /sign-in/email", async () => {
      const email = uniqueEmail("closed-signin");
      const password = "correcthorsebatterystaple123";
      const ip = randomIp();
      await post(
        testApp,
        "/sign-up/email",
        { email, password, name: "Admin Backoffice" },
        ip,
      );

      const response = await post(
        closedApp,
        "/sign-in/email",
        { email, password },
        ip,
      );

      expect(response.status).toBe(200);
    });
  });

  describe("fixed dev code for @stravaclone.test", () => {
    let devApp: TestAuthApp;

    beforeAll(async () => {
      devApp = await bootstrapTestAuthApp({ nodeEnv: "development" });
    });

    afterAll(async () => {
      await devApp.app.close();
    });

    function testAddress(label: string): string {
      return `${label}-${Date.now()}-${Math.random().toString(36).slice(2)}@stravaclone.test`;
    }

    it("signs a @stravaclone.test address in with 000000 in development, without any email", async () => {
      const email = testAddress("dev");
      const ip = randomIp();
      const spy = vi.spyOn(devApp.notificationsService, "sendAuthEmail");
      spy.mockClear();
      await post(
        devApp,
        "/email-otp/send-verification-otp",
        { email, type: "sign-in" },
        ip,
      );

      const response = await signInWithCode(
        devApp,
        { email, otp: "000000" },
        ip,
      );

      expect(response.status).toBe(200);
      expect(spy).not.toHaveBeenCalled();
    });

    it("keeps a random, emailed code for other addresses in development", async () => {
      const email = uniqueEmail("dev-other");
      const ip = randomIp();
      const otp = await requestCode(devApp, email, ip);

      const response = await signInWithCode(devApp, { email, otp }, ip);

      expect(response.status).toBe(200);
    });

    it("does not accept 000000 for a @stravaclone.test address outside development", async () => {
      const email = testAddress("not-dev");
      const ip = randomIp();
      const otp = await requestCode(testApp, email, ip);

      const response = await signInWithCode(
        testApp,
        { email, otp: otp === "000000" ? "111111" : "000000" },
        ip,
      );

      expect(response.status).toBe(400);
    });
  });
});
