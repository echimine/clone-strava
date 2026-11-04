export interface NotificationsModuleOptions {
  /** Resend API key; without it nothing is sent (`sendEmail` reports it), e.g. a local worker. */
  apiKey?: string;
  /** Only `POST /v1/webhooks/resend` needs it (`verifyWebhookSignature`). */
  webhookSecret?: string;
}

export const NOTIFICATIONS_OPTIONS = Symbol("NOTIFICATIONS_OPTIONS");
