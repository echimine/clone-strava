import { z } from "zod";
import { requestIdFieldSchema } from "../common/request-id.js";

/**
 * Domain events emitted by the `activities` module after commit (ADR-011
 * §5, ADR-021 §3-4). The realtime bridge (`realtime` platform module, see
 * `@repo/realtime`) maps these onto the mobile protocol (`activity.processed`
 * / `activity.failed`); domain modules never publish to Redis themselves.
 */
export const ACTIVITY_PROCESSED_EVENT = "activities.activity.processed";
export const ACTIVITY_FAILED_EVENT = "activities.activity.failed";

/** Minimal payload (ADR-021 §3: "identifiers and what the listeners need"). */
export const activityProcessedEventSchema = z.object({
  activityId: z.uuid(),
  userId: z.uuid(),
  status: z.literal("processed"),
  requestId: requestIdFieldSchema,
});
export type ActivityProcessedEvent = z.infer<typeof activityProcessedEventSchema>;

export const activityFailedEventSchema = z.object({
  activityId: z.uuid(),
  userId: z.uuid(),
  status: z.literal("failed"),
  requestId: requestIdFieldSchema,
});
export type ActivityFailedEvent = z.infer<typeof activityFailedEventSchema>;
