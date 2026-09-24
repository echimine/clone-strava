import { z } from "zod";

/**
 * `POST /v1/webhooks/revenuecat` body (ADR-014). Validated loosely
 * (`passthrough`-style): the API only needs the event `id` (deduplication)
 * and `type` for logging before enqueueing `sync-subscription`; the worker
 * re-reads the authoritative state from the RevenueCat REST API rather than
 * trusting this body (ADR-014, rejected alternative: "Apply the webhook
 * content without re-reading the full state").
 */
export const revenueCatWebhookEventSchema = z.looseObject({
  id: z.string(),
  type: z.string(),
  app_user_id: z.string(),
});
export type RevenueCatWebhookEvent = z.infer<typeof revenueCatWebhookEventSchema>;

export const revenueCatWebhookBodySchema = z.looseObject({
  api_version: z.string().optional(),
  event: revenueCatWebhookEventSchema,
});
export type RevenueCatWebhookBody = z.infer<typeof revenueCatWebhookBodySchema>;
