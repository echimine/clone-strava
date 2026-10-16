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
/** The author deleted the activity, emitted after the commit (ADR-033 §6). */
export const ACTIVITY_DELETED_EVENT = "activities.activity.deleted";

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

/** The author edited the activity (ADR-033 §4), emitted after the commit. */
export const ACTIVITY_UPDATED_EVENT = "activities.activity.updated";

/**
 * What changed in an `activities.activity.updated` event: the edited fields (ADR-033 §4, names
 * of `updateActivityRequestSchema`), or `stats` once a reprocessing lands (ADR-033 §5).
 */
export const activityChangedFieldSchema = z.enum(["title", "description", "sportTypeCode", "visibility", "stats"]);
export type ActivityChangedField = z.infer<typeof activityChangedFieldSchema>;

export const activityUpdatedEventSchema = z.object({
  activityId: z.uuid(),
  userId: z.uuid(),
  changedFields: z.array(activityChangedFieldSchema).min(1),
});
export type ActivityUpdatedEvent = z.infer<typeof activityUpdatedEventSchema>;

export const activityDeletedEventSchema = z.object({
  activityId: z.uuid(),
  userId: z.uuid(),
});
export type ActivityDeletedEvent = z.infer<typeof activityDeletedEventSchema>;

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
