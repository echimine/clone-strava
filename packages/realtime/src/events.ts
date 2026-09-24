import { z } from "zod";

/**
 * Mobile event types (ADR-010 §5), as sent to the client in the envelope's
 * `t` field. The realtime bridge (ADR-021 §4) maps internal domain events
 * onto these public names, so internal refactoring never breaks the app.
 */
export const ACTIVITY_PROCESSED = "activity.processed";
export const ACTIVITY_FAILED = "activity.failed";
export const ACTIVITY_SEGMENTS_MATCHED = "activity.segments_matched";

export const mobileEventTypeSchema = z.enum([
  ACTIVITY_PROCESSED,
  ACTIVITY_FAILED,
  ACTIVITY_SEGMENTS_MATCHED,
]);
export type MobileEventType = z.infer<typeof mobileEventTypeSchema>;

/**
 * Minimal per-event data schemas (ADR-010 §5): identifiers only, never the
 * resource itself. The mobile app reloads the resource through the API.
 */
export const activityProcessedDataSchema = z.object({
  activityId: z.string(),
  status: z.literal("processed"),
  at: z.iso.datetime(),
});
export type ActivityProcessedData = z.infer<typeof activityProcessedDataSchema>;

export const activityFailedDataSchema = z.object({
  activityId: z.string(),
  status: z.literal("failed"),
  at: z.iso.datetime(),
});
export type ActivityFailedData = z.infer<typeof activityFailedDataSchema>;

export const activitySegmentsMatchedDataSchema = z.object({
  activityId: z.string(),
  status: z.literal("segments_matched"),
  at: z.iso.datetime(),
});
export type ActivitySegmentsMatchedData = z.infer<
  typeof activitySegmentsMatchedDataSchema
>;

/** Data schema for each mobile event type, keyed by its `t` value. */
export const mobileEventDataSchemas = {
  [ACTIVITY_PROCESSED]: activityProcessedDataSchema,
  [ACTIVITY_FAILED]: activityFailedDataSchema,
  [ACTIVITY_SEGMENTS_MATCHED]: activitySegmentsMatchedDataSchema,
} as const satisfies Record<MobileEventType, z.ZodType>;

export type MobileEventData =
  | ActivityProcessedData
  | ActivityFailedData
  | ActivitySegmentsMatchedData;

/** Data payload type for a given mobile event type, e.g. `MobileEventDataFor<typeof ACTIVITY_PROCESSED>`. */
export type MobileEventDataFor<T extends MobileEventType> = z.infer<
  (typeof mobileEventDataSchemas)[T]
>;
