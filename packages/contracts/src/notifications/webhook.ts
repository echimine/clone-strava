import { z } from "zod";

/**
 * `POST /v1/webhooks/resend` body (ADR-023). The webhook (Resend dashboard,
 * id `efa1617e-1df0-4625-8174-b0a569d5622f`) is subscribed only to
 * `email.bounced`, `email.complained`, and `email.delivery_delayed`, but
 * `type` stays a permissive `z.string()` (not a closed enum) so an unrelated
 * event type Resend might add to the subscription later doesn't fail
 * validation -- the controller no-ops on anything it doesn't recognize
 * rather than rejecting it.
 *
 * Validated loosely (`z.looseObject`, like `revenueCatWebhookBodySchema`):
 * the API only needs `type` (dispatch) and `data.to` (which user's email to
 * flag) before delegating to `NotificationsService`/`AuthService`, and
 * Resend's payload carries more fields than that (`data.email_id`,
 * `data.subject`, `data.bounce`/`data.complaint` details, ...) that aren't
 * needed here.
 */
export const resendWebhookBodySchema = z.looseObject({
  type: z.string(),
  created_at: z.string().optional(),
  data: z.looseObject({
    email_id: z.string().optional(),
    to: z.array(z.string()).optional(),
  }),
});
export type ResendWebhookBody = z.infer<typeof resendWebhookBodySchema>;
