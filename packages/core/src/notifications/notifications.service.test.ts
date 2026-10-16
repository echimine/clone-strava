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

describe("NotificationsService.sendAuthEmail", () => {
  beforeEach(() => {
    send.mockReset();
    send.mockResolvedValue({ data: { id: "email-id" }, error: null });
  });

  it("sends from Nervo on the mail.strava.echimine.fr domain", async () => {
    const service = new NotificationsService({ apiKey: "re_test", webhookSecret: "whsec_test" });

    await service.sendAuthEmail({
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
});
