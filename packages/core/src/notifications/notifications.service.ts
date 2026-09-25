import { Inject, Injectable, Logger } from "@nestjs/common";
import type { Resend, WebhookEventPayload } from "resend";
import { NOTIFICATIONS_OPTIONS, type NotificationsModuleOptions } from "./notifications.constants.js";
import { createResendClient } from "./resend-client.js";

export interface SendAuthEmailParams {
  to: string;
  subject: string;
  html: string;
  idempotencyKey: string;
}

/**
 * Svix headers Resend signs webhook payloads with (ADR-023), keyed as the
 * `resend` SDK's `Webhooks.verify()` expects them — plain `id`/`timestamp`/
 * `signature`, not the raw `svix-*` header names. Map the raw request
 * headers to this shape at the controller boundary:
 * `{ id: req.headers["svix-id"], timestamp: req.headers["svix-timestamp"], signature: req.headers["svix-signature"] }`.
 */
export interface ResendWebhookHeaders {
  id: string;
  timestamp: string;
  signature: string;
}

/**
 * `notifications` platform module (ADR-023): owns no table, no business
 * rule, wraps `resend`. Every domain module and app may import it, same
 * as `analytics`/`storage` (ADR-021 §2).
 */
@Injectable()
export class NotificationsService {
  private readonly logger = new Logger(NotificationsService.name);
  private readonly client: Resend;
  private readonly webhookSecret: string;

  constructor(@Inject(NOTIFICATIONS_OPTIONS) options: NotificationsModuleOptions) {
    this.client = createResendClient(options.apiKey);
    this.webhookSecret = options.webhookSecret;
  }

  /**
   * Sends a transactional auth email (signup verification, password reset,
   * admin OTP). Never throws: the Resend Node SDK returns `{ data, error }`
   * for API-level errors rather than throwing, and this method preserves
   * that contract — an email failure must not fail the auth flow that
   * triggered it (ADR-023).
   */
  async sendAuthEmail(params: SendAuthEmailParams): Promise<void> {
    const { error } = await this.client.emails.send(
      {
        from: "Clone Strava <noreply@mail.strava.echimine.fr>",
        to: params.to,
        subject: params.subject,
        html: params.html,
      },
      { idempotencyKey: params.idempotencyKey },
    );

    if (error) {
      this.logger.error(
        `Failed to send auth email (idempotencyKey=${params.idempotencyKey}): ${error.message}`,
        error,
      );
    }
  }

  /**
   * Verifies a Resend webhook's Svix signature and returns the parsed
   * event, or `null` if the signature is invalid. `payload` must be the
   * raw request body string (never re-serialized JSON — see ADR-023's
   * raw-body note for `POST /v1/webhooks/resend`). Unlike `emails.send`,
   * the SDK's `webhooks.verify()` throws on failure — this method is the
   * only place that catches that throw, so the webhook controller never
   * touches the SDK directly and never needs a try/catch of its own.
   */
  verifyWebhookSignature(payload: string, headers: ResendWebhookHeaders): WebhookEventPayload | null {
    try {
      return this.client.webhooks.verify({
        payload,
        headers,
        webhookSecret: this.webhookSecret,
      });
    } catch (error) {
      this.logger.warn(`Webhook signature verification failed: ${(error as Error).message}`);
      return null;
    }
  }
}
