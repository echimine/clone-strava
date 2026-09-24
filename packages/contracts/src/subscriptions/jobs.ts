import { z } from "zod";
import { requestIdFieldSchema } from "../common/request-id.js";

/** `subscriptions` queue (ADR-011, ADR-014). */
export const SUBSCRIPTIONS_QUEUE_NAME = "subscriptions";
/** `sync-subscription` job (ADR-011, ADR-014 "Backend side"). */
export const SYNC_SUBSCRIPTION_JOB_NAME = "sync-subscription";

/** Deterministic job id derived from the entity (ADR-011 §2). */
export function syncSubscriptionJobId(userId: string): string {
  return `sync-subscription:${userId}`;
}

/**
 * `sync-subscription` job payload (ADR-014): the worker re-reads the full
 * subscriber state from the RevenueCat REST API using `userId`, rather than
 * trusting the webhook body.
 */
export const syncSubscriptionJobSchema = z.object({
  userId: z.uuid(),
  requestId: requestIdFieldSchema,
});
export type SyncSubscriptionJob = z.infer<typeof syncSubscriptionJobSchema>;
