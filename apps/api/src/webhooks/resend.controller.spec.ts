import { Webhook } from "standardwebhooks";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { AuthService } from "@repo/core/auth";
import { NotificationsService } from "@repo/core/notifications";
import { ResendWebhookController } from "./resend.controller.js";

/**
 * Svix-compatible test secret (ADR-023): `standardwebhooks`'s `Webhook`
 * class strips a `whsec_` prefix and base64-decodes the rest (its own
 * source, `node_modules/standardwebhooks/dist/index.js`), so this must be
 * valid base64 -- a throwaway, test-only secret, never the real Resend
 * webhook signing secret (fetched only via the Resend MCP, never hardcoded
 * in a test file, per coder-webhook's handoff).
 */
const TEST_WEBHOOK_SECRET = "whsec_dGVzdC1vbmx5LXNlY3JldC1kby1ub3QtdXNl";

function buildRawBodyRequest(body: unknown, headers: Record<string, string | undefined>) {
  const rawBody = Buffer.from(JSON.stringify(body), "utf-8");
  return {
    request: { rawBody } as { rawBody?: Buffer },
    headers,
    body,
  };
}

/** Signs `body` with the given secret using the same scheme Resend/Svix use. */
function signBody(body: unknown, secret: string, msgId = "msg_test_1", timestamp = new Date()) {
  const payload = JSON.stringify(body);
  const webhook = new Webhook(secret);
  const signature = webhook.sign(msgId, timestamp, payload);
  return {
    "svix-id": msgId,
    "svix-timestamp": String(Math.floor(timestamp.getTime() / 1000)),
    "svix-signature": signature,
  };
}

describe("ResendWebhookController (POST /v1/webhooks/resend, ADR-023)", () => {
  let controller: ResendWebhookController;
  let notificationsService: NotificationsService;
  let markEmailUnverified: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    // Real NotificationsService (not a mock): the whole point of this test
    // is exercising its actual Svix verification against real signed/
    // tampered fixtures, not a stubbed yes/no.
    notificationsService = new NotificationsService({
      apiKey: "test-resend-api-key-unused-by-verify",
      webhookSecret: TEST_WEBHOOK_SECRET,
    });
    markEmailUnverified = vi.fn().mockResolvedValue(undefined);
    const authService = { markEmailUnverified } as unknown as AuthService;
    controller = new ResendWebhookController(notificationsService, authService);
  });

  it("accepts a validly-signed email.bounced payload and flags the recipient's email unverified", async () => {
    const body = {
      type: "email.bounced",
      created_at: new Date().toISOString(),
      data: { email_id: "email_123", to: ["bounced@example.com"] },
    };
    const signedHeaders = signBody(body, TEST_WEBHOOK_SECRET);
    const { request } = buildRawBodyRequest(body, signedHeaders);

    const result = await controller.handle(
      request as never,
      signedHeaders["svix-id"],
      signedHeaders["svix-timestamp"],
      signedHeaders["svix-signature"],
      body as never,
    );

    expect(result).toEqual({ received: true });
    expect(markEmailUnverified).toHaveBeenCalledExactlyOnceWith("bounced@example.com");
  });

  it("accepts a validly-signed email.complained payload the same way", async () => {
    const body = {
      type: "email.complained",
      data: { email_id: "email_456", to: ["complained@example.com"] },
    };
    const signedHeaders = signBody(body, TEST_WEBHOOK_SECRET);
    const { request } = buildRawBodyRequest(body, signedHeaders);

    const result = await controller.handle(
      request as never,
      signedHeaders["svix-id"],
      signedHeaders["svix-timestamp"],
      signedHeaders["svix-signature"],
      body as never,
    );

    expect(result).toEqual({ received: true });
    expect(markEmailUnverified).toHaveBeenCalledExactlyOnceWith("complained@example.com");
  });

  it("acks email.delivery_delayed without flagging any email (log only, ADR-023)", async () => {
    const body = { type: "email.delivery_delayed", data: { email_id: "email_789", to: ["slow@example.com"] } };
    const signedHeaders = signBody(body, TEST_WEBHOOK_SECRET);
    const { request } = buildRawBodyRequest(body, signedHeaders);

    const result = await controller.handle(
      request as never,
      signedHeaders["svix-id"],
      signedHeaders["svix-timestamp"],
      signedHeaders["svix-signature"],
      body as never,
    );

    expect(result).toEqual({ received: true });
    expect(markEmailUnverified).not.toHaveBeenCalled();
  });

  it("rejects a tampered payload (signature no longer matches) with 401", async () => {
    const originalBody = { type: "email.bounced", data: { email_id: "email_123", to: ["victim@example.com"] } };
    const signedHeaders = signBody(originalBody, TEST_WEBHOOK_SECRET);
    // Tamper: attacker swaps the target email after the signature was computed.
    const tamperedBody = { type: "email.bounced", data: { email_id: "email_123", to: ["attacker@example.com"] } };
    const { request } = buildRawBodyRequest(tamperedBody, signedHeaders);

    await expect(
      controller.handle(
        request as never,
        signedHeaders["svix-id"],
        signedHeaders["svix-timestamp"],
        signedHeaders["svix-signature"],
        tamperedBody as never,
      ),
    ).rejects.toMatchObject({ status: 401 });
    expect(markEmailUnverified).not.toHaveBeenCalled();
  });

  it("rejects a payload signed with the wrong secret with 401", async () => {
    const body = { type: "email.bounced", data: { email_id: "email_123", to: ["victim@example.com"] } };
    const wrongSecretHeaders = signBody(body, "whsec_d3Jvbmctc2VjcmV0LWZvci10ZXN0LW9ubHk=");
    const { request } = buildRawBodyRequest(body, wrongSecretHeaders);

    await expect(
      controller.handle(
        request as never,
        wrongSecretHeaders["svix-id"],
        wrongSecretHeaders["svix-timestamp"],
        wrongSecretHeaders["svix-signature"],
        body as never,
      ),
    ).rejects.toMatchObject({ status: 401 });
  });

  it("rejects a request missing the raw body with 400 (should never happen given main.ts's scoped verify, but must fail loudly)", async () => {
    const body = { type: "email.bounced", data: { to: ["x@example.com"] } };
    const request = {} as { rawBody?: Buffer };

    await expect(
      controller.handle(request as never, "msg_1", "1700000000", "v1,fakesignature==", body as never),
    ).rejects.toMatchObject({ status: 400 });
  });

  it("rejects a request missing any Svix header with 400", async () => {
    const body = { type: "email.bounced", data: { to: ["x@example.com"] } };
    const rawBody = Buffer.from(JSON.stringify(body), "utf-8");
    const request = { rawBody } as { rawBody?: Buffer };

    await expect(
      controller.handle(request as never, undefined, "1700000000", "v1,fakesignature==", body as never),
    ).rejects.toMatchObject({ status: 400 });
  });

  it("acks (no-ops) an unknown event type without erroring or flagging any email", async () => {
    const body = { type: "email.opened", data: { to: ["someone@example.com"] } };
    const signedHeaders = signBody(body, TEST_WEBHOOK_SECRET);
    const { request } = buildRawBodyRequest(body, signedHeaders);

    const result = await controller.handle(
      request as never,
      signedHeaders["svix-id"],
      signedHeaders["svix-timestamp"],
      signedHeaders["svix-signature"],
      body as never,
    );

    expect(result).toEqual({ received: true });
    expect(markEmailUnverified).not.toHaveBeenCalled();
  });
});
