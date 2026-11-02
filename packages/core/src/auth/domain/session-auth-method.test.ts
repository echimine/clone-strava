import { describe, expect, it } from "vitest";
import { sessionAuthMethodFor } from "./session-auth-method.js";

describe("sessionAuthMethodFor (ADR-035 §3)", () => {
  it.each([
    ["/two-factor/verify-totp", "password_2fa"],
    ["/two-factor/verify-otp", "password_2fa"],
    ["/two-factor/verify-backup-code", "password_2fa"],
    ["/sign-in/email", "password"],
    ["/sign-up/email", "password"],
    ["/sign-in/email-otp", "email_otp"],
    ["/sign-in/social", "google"],
    ["/callback/google", "google"],
  ])("maps %s to %s", (path, expected) => {
    expect(sessionAuthMethodFor({ path })).toBe(expected);
  });

  it("maps the OAuth callback route pattern to google when the provider is google", () => {
    expect(sessionAuthMethodFor({ path: "/callback/:id", params: { id: "google" } })).toBe("google");
  });

  it("gives no method (weak) to another provider's callback", () => {
    expect(sessionAuthMethodFor({ path: "/callback/:id", params: { id: "github" } })).toBeNull();
    expect(sessionAuthMethodFor({ path: "/callback/github" })).toBeNull();
  });

  it.each(["/change-password", "/two-factor/enable", "/admin/impersonate-user", "/sign-in/emailx", ""])(
    "gives no method (weak) to the unknown path %j",
    (path) => {
      expect(sessionAuthMethodFor({ path })).toBeNull();
    },
  );

  it("gives no method (weak) without an endpoint context", () => {
    expect(sessionAuthMethodFor(null)).toBeNull();
    expect(sessionAuthMethodFor({})).toBeNull();
  });
});
