import { describe, expect, it } from "vitest";
import { renderAdminOtpEmail, renderResetPasswordEmail, renderVerifyEmail } from "./index.js";

/** Auth emails carry the Nervo brand (ADR-032 §1), never the old project names. */
describe("auth emails", () => {
  const cases = [
    ["verify email", () => renderVerifyEmail({ url: "https://example.com/verify" })],
    ["reset password", () => renderResetPasswordEmail({ url: "https://example.com/reset" })],
    ["admin OTP", () => renderAdminOtpEmail({ otp: "123456", email: "jdoe@example.com" })],
  ] as const;

  it.each(cases)("%s email is branded Nervo", async (_name, render) => {
    const html = await render();

    expect(html).toContain("Nervo");
    expect(html).not.toMatch(/Clone Strava|Like-Strava|StravaClone/);
  });
});
