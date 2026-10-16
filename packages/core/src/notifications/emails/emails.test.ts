import { describe, expect, it } from "vitest";
import { emailWordmarkUrl } from "./email-layout.js";
import { renderAdminOtpEmail, renderResetPasswordEmail, renderVerifyEmail } from "./index.js";

const logoUrl = "https://admin.example.com/brand/nervo-wordmark-email.png";

/** ADR-032 §2: the backoffice hosts the wordmark PNG, outside its login proxy. */
describe("email wordmark URL", () => {
  it("is the hosted PNG on the backoffice origin", () => {
    expect(emailWordmarkUrl("https://admin.example.com")).toBe(
      "https://admin.example.com/brand/nervo-wordmark-email.png",
    );
  });
});

/** Auth emails carry the Nervo brand (ADR-032 §1), never the old project names. */
describe("auth emails", () => {
  const cases = [
    ["verify", () => renderVerifyEmail({ url: "https://example.com/verify", logoUrl })],
    ["reset password", () => renderResetPasswordEmail({ url: "https://example.com/reset", logoUrl })],
    ["admin OTP", () => renderAdminOtpEmail({ otp: "123456", email: "jdoe@example.com", logoUrl })],
  ] as const;

  it.each(cases)("%s email is branded Nervo", async (_name, render) => {
    const html = await render();

    expect(html).toContain("Nervo");
    expect(html).not.toMatch(/Clone Strava|Like-Strava|StravaClone/);
  });

  // ADR-032 §2: a hosted PNG (email clients do not render SVG) on an orange band.
  it.each(cases)("%s email opens with the wordmark on a #FC5200 band", async (_name, render) => {
    const html = await render();

    const image = /<img[^>]*>/.exec(html)?.[0];
    expect(image).toContain(`src="${logoUrl}"`);
    expect(image).toContain('alt="Nervo"');
    expect(html).toMatch(/background-color:#FC5200[^>]*>(?:(?!<\/td>)[\s\S])*<img/);
  });

  it.each(cases.slice(0, 2))("%s email has a #FC5200 action button", async (_name, render) => {
    const html = await render();

    expect(html).toMatch(/<a[^>]*background-color:#FC5200/);
    expect(html).not.toContain("#fc4c02");
  });
});
