import { z } from "zod";
import { requestIdFieldSchema } from "../common/request-id.js";
import { activityImportErrorCodeSchema } from "./import.js";

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

/** Emitted after the `import-activity` commit (ADR-028 §4 step 11, §10). */
export const ACTIVITY_IMPORT_COMPLETED_EVENT = "activities.import.completed";
export const ACTIVITY_IMPORT_FAILED_EVENT = "activities.import.failed";

export const activityImportCompletedEventSchema = z.object({
  importId: z.uuid(),
  /** Created activity (`imported`) or existing one (`duplicate`). */
  activityId: z.uuid(),
  userId: z.uuid(),
  outcome: z.enum(["imported", "duplicate"]),
  requestId: requestIdFieldSchema,
});
export type ActivityImportCompletedEvent = z.infer<typeof activityImportCompletedEventSchema>;

export const activityImportFailedEventSchema = z.object({
  importId: z.uuid(),
  userId: z.uuid(),
  code: activityImportErrorCodeSchema,
  requestId: requestIdFieldSchema,
});
export type ActivityImportFailedEvent = z.infer<typeof activityImportFailedEventSchema>;
