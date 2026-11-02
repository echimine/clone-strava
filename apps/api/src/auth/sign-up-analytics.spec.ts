import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi, type MockInstance } from "vitest";
import { AnalyticsService } from "@repo/core/analytics";
import { bootstrapTestAuthApp, ensureTestDatabaseMigrated, type TestAuthApp } from "./test-auth-app.js";
import { fakeGoogleIdTokens } from "./test-google-id-token.js";

/**
 * `user_signed_up {method}` (ADR-035 §8): sent by the Better Auth hook when
 * an account is created, by Sign-in code or by Google, never on a plain
 * sign-in. Real Better Auth mount, Postgres and Redis; `AnalyticsService.
 * capture` is spied on. Google's ID tokens are signed with a local key whose
 * public half is served in place of Google's certificates (the only faked
 * `fetch`).
 */
describe("user_signed_up (ADR-035 §8)", () => {
  let testApp: TestAuthApp;
  let capture: MockInstance<AnalyticsService["capture"]>;
  let google: ReturnType<typeof fakeGoogleIdTokens>;

  beforeAll(async () => {
    await ensureTestDatabaseMigrated();
    testApp = await bootstrapTestAuthApp();
    capture = vi.spyOn(testApp.app.get(AnalyticsService), "capture");
    google = fakeGoogleIdTokens();
  });

  afterAll(async () => {
    vi.restoreAllMocks();
    await testApp.app.close();
  });

  beforeEach(() => {
    capture.mockClear();
  });

  function uniqueEmail(label: string): string {
    return `${label}-${Date.now()}-${Math.random().toString(36).slice(2)}@example.com`;
  }

  /** A random address in 10.0.0.0/8, so no two tests share a rate-limit budget. */
  function randomIp(): string {
    const byte = () => Math.floor(Math.random() * 254) + 1;
    return `10.${byte()}.${byte()}.${byte()}`;
  }

  function post(path: string, body: unknown, ip: string): Promise<Response> {
    return fetch(`${testApp.baseUrl}/api/auth${path}`, {
      method: "POST",
      headers: { "content-type": "application/json", "x-forwarded-for": ip },
      body: JSON.stringify(body),
    });
  }

  /** Requests a code, reads it from the email, and signs in with it. */
  async function signInWithCode(email: string, ip: string): Promise<{ id: string }> {
    const spy = vi.spyOn(testApp.notificationsService, "sendAuthEmail");
    spy.mockClear();
    expect((await post("/email-otp/send-verification-otp", { email, type: "sign-in" }, ip)).status).toBe(200);
    const html = spy.mock.calls.find((call) => call[0].to === email)?.[0].html ?? "";
    const otp = /\b\d{6}\b/.exec(html.replace(/<[^>]*>/g, " "))?.[0];
    const response = await post("/sign-in/email-otp", { email, otp, name: "Jeanne Martin" }, ip);
    expect(response.status).toBe(200);
    return ((await response.json()) as { user: { id: string } }).user;
  }

  async function signInWithGoogle(email: string, sub: string): Promise<{ id: string }> {
    const response = await post(
      "/sign-in/social",
      { provider: "google", idToken: { token: google.idToken(email, sub) } },
      randomIp(),
    );
    expect(response.status).toBe(200);
    return ((await response.json()) as { user: { id: string } }).user;
  }

  function signUps() {
    return capture.mock.calls.filter(([event]) => event === "user_signed_up");
  }

  it("is sent once, with method email_code, when a Sign-in code creates the account", async () => {
    const user = await signInWithCode(uniqueEmail("signup-code"), randomIp());

    await vi.waitFor(() => expect(signUps()).toEqual([["user_signed_up", user.id, { method: "email_code" }]]));
  });

  it("is not sent when a later code signs the same account in", async () => {
    const email = uniqueEmail("signin-code");
    const ip = randomIp();
    await signInWithCode(email, ip);
    await vi.waitFor(() => expect(signUps()).toHaveLength(1));
    capture.mockClear();

    await signInWithCode(email, ip);

    await new Promise((resolve) => setTimeout(resolve, 200));
    expect(signUps()).toEqual([]);
  });

  it("is sent once, with method google, when Google creates the account", async () => {
    const user = await signInWithGoogle(uniqueEmail("signup-google"), randomUUID());

    await vi.waitFor(() => expect(signUps()).toEqual([["user_signed_up", user.id, { method: "google" }]]));
  });

  it("is not sent when Google signs an existing account in", async () => {
    const email = uniqueEmail("signin-google");
    const sub = randomUUID();
    await signInWithGoogle(email, sub);
    await vi.waitFor(() => expect(signUps()).toHaveLength(1));
    capture.mockClear();

    await signInWithGoogle(email, sub);

    await new Promise((resolve) => setTimeout(resolve, 200));
    expect(signUps()).toEqual([]);
  });
});
