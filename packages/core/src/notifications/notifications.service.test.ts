import { beforeEach, describe, expect, it, vi } from "vitest";
import { NotificationsService } from "./notifications.service.js";

const { send } = vi.hoisted(() => ({ send: vi.fn() }));

// Resend is the external boundary (ADR-023): replace the SDK, not our own code.
vi.mock("resend", () => ({
  Resend: class {
    emails = { send };
    webhooks = { verify: vi.fn() };
  },
}));

describe("NotificationsService.sendEmail", () => {
  beforeEach(() => {
    send.mockReset();
    send.mockResolvedValue({ data: { id: "email-id" }, error: null });
  });

  it("sends from Nervo on the mail.strava.echimine.fr domain", async () => {
    const service = new NotificationsService({ apiKey: "re_test", webhookSecret: "whsec_test" });

    await service.sendEmail({
      to: "jdoe@example.com",
      subject: "Verify your email",
      html: "<p>hi</p>",
      idempotencyKey: "verify-email/1",
    });

    expect(send).toHaveBeenCalledWith(
      expect.objectContaining({ from: "Nervo <noreply@mail.strava.echimine.fr>" }),
      { idempotencyKey: "verify-email/1" },
    );
  });

  // ADR-038 §4: the athlete contests a Sanction by replying to the team's address.
  it("sets the Reply-To when given one, and none otherwise", async () => {
    const service = new NotificationsService({ apiKey: "re_test", webhookSecret: "whsec_test" });

    await service.sendEmail({ to: "a@example.com", subject: "s", html: "<p/>", idempotencyKey: "k1", replyTo: "contact@example.com" });
    await service.sendEmail({ to: "a@example.com", subject: "s", html: "<p/>", idempotencyKey: "k2" });

    expect(send.mock.calls[0]?.[0]).toMatchObject({ replyTo: "contact@example.com" });
    expect(send.mock.calls[1]?.[0]).not.toHaveProperty("replyTo");
  });

  it("reports a sent e-mail and never throws on a Resend error", async () => {
    const service = new NotificationsService({ apiKey: "re_test", webhookSecret: "whsec_test" });
    send.mockResolvedValueOnce({ data: null, error: { name: "rate_limit_exceeded", message: "Too many requests" } });

    const failed = await service.sendEmail({ to: "a@example.com", subject: "s", html: "<p/>", idempotencyKey: "k1" });
    const sent = await service.sendEmail({ to: "a@example.com", subject: "s", html: "<p/>", idempotencyKey: "k2" });

    expect(failed).toEqual({ sent: false, error: "rate_limit_exceeded: Too many requests" });
    expect(sent).toEqual({ sent: true });
  });

  // The worker may run without a Resend key (local dev): nothing is sent, nothing throws.
  it("sends nothing without an API key", async () => {
    const service = new NotificationsService({});

    const result = await service.sendEmail({ to: "a@example.com", subject: "s", html: "<p/>", idempotencyKey: "k1" });

    expect(result).toEqual({ sent: false, error: "RESEND_API_KEY is not configured" });
    expect(send).not.toHaveBeenCalled();
  });
});
