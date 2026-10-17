import { z } from "zod";

/**
 * Mobile event types (ADR-010 §5), as sent to the client in the envelope's
 * `t` field. The realtime bridge (ADR-021 §4) maps internal domain events
 * onto these public names, so internal refactoring never breaks the app.
 */
export const ACTIVITY_PROCESSED = "activity.processed";
export const ACTIVITY_FAILED = "activity.failed";
export const ACTIVITY_SEGMENTS_MATCHED = "activity.segments_matched";
/** The author edited the activity, or its reprocessing landed (ADR-033 §8). */
export const ACTIVITY_UPDATED = "activity.updated";
/** The author deleted the activity (ADR-033 §8). */
export const ACTIVITY_DELETED = "activity.deleted";
/** File imports (ADR-028 §10). */
export const ACTIVITY_IMPORT_COMPLETED = "activity_import.completed";
export const ACTIVITY_IMPORT_FAILED = "activity_import.failed";
/** Itineraries (ADR-030 §9). */
export const ITINERARY_SAVED = "itinerary.saved";
export const ITINERARY_DELETED = "itinerary.deleted";
/** Comments and kudos of an Activity, on `activity:{id}` (ADR-034 §5). */
export const COMMENT_CREATED = "comment.created";
export const COMMENT_UPDATED = "comment.updated";
export const COMMENT_DELETED = "comment.deleted";
export const KUDOS_CHANGED = "kudos.changed";

export const mobileEventTypeSchema = z.enum([
  ACTIVITY_PROCESSED,
  ACTIVITY_FAILED,
  ACTIVITY_SEGMENTS_MATCHED,
  ACTIVITY_UPDATED,
  ACTIVITY_DELETED,
  ACTIVITY_IMPORT_COMPLETED,
  ACTIVITY_IMPORT_FAILED,
  ITINERARY_SAVED,
  ITINERARY_DELETED,
  COMMENT_CREATED,
  COMMENT_UPDATED,
  COMMENT_DELETED,
  KUDOS_CHANGED,
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

/**
 * `changedFields`: `title`, `description`, `sportTypeCode`, `visibility` (an edit) or `stats`
 * (a reprocessing). The app reloads the card and an open detail; the echo of its own write is
 * harmless.
 */
export const activityUpdatedDataSchema = z.object({
  activityId: z.string(),
  changedFields: z.array(z.string()),
});
export type ActivityUpdatedData = z.infer<typeof activityUpdatedDataSchema>;

/** The app drops the card and switches an open detail to its unavailable state. */
export const activityDeletedDataSchema = z.object({
  activityId: z.string(),
});
export type ActivityDeletedData = z.infer<typeof activityDeletedDataSchema>;

/** `activityId`: the created activity (`imported`) or the existing one (`duplicate`). */
export const activityImportCompletedDataSchema = z.object({
  importId: z.string(),
  activityId: z.string(),
  status: z.enum(["imported", "duplicate"]),
  at: z.iso.datetime(),
});
export type ActivityImportCompletedData = z.infer<typeof activityImportCompletedDataSchema>;

/** `code`: the import error code (ADR-028 §7), the only thing the app shows; no personal data. */
export const activityImportFailedDataSchema = z.object({
  importId: z.string(),
  status: z.literal("failed"),
  code: z.string(),
  at: z.iso.datetime(),
});
export type ActivityImportFailedData = z.infer<typeof activityImportFailedDataSchema>;

/**
 * Creation, full update or rename. The app ignores it when its local
 * `updatedAt` is already greater or equal (the echo of its own write),
 * otherwise it fetches the detail.
 */
export const itinerarySavedDataSchema = z.object({
  itineraryId: z.string(),
  updatedAt: z.iso.datetime(),
});
export type ItinerarySavedData = z.infer<typeof itinerarySavedDataSchema>;

export const itineraryDeletedDataSchema = z.object({
  itineraryId: z.string(),
});
export type ItineraryDeletedData = z.infer<typeof itineraryDeletedDataSchema>;

/**
 * `comment.created` / `comment.updated` / `comment.deleted`. The app ignores
 * the echo of its own write when it already knows the comment in that state,
 * otherwise it fetches that one comment (or removes it locally on delete).
 */
export const commentEventDataSchema = z.object({
  activityId: z.string(),
  commentId: z.string(),
});
export type CommentEventData = z.infer<typeof commentEventDataSchema>;

/** Someone gave or removed kudos: the app reloads the detail's engagement. */
export const kudosChangedDataSchema = z.object({
  activityId: z.string(),
});
export type KudosChangedData = z.infer<typeof kudosChangedDataSchema>;

/** Data schema for each mobile event type, keyed by its `t` value. */
export const mobileEventDataSchemas = {
  [ACTIVITY_PROCESSED]: activityProcessedDataSchema,
  [ACTIVITY_FAILED]: activityFailedDataSchema,
  [ACTIVITY_SEGMENTS_MATCHED]: activitySegmentsMatchedDataSchema,
  [ACTIVITY_UPDATED]: activityUpdatedDataSchema,
  [ACTIVITY_DELETED]: activityDeletedDataSchema,
  [ACTIVITY_IMPORT_COMPLETED]: activityImportCompletedDataSchema,
  [ACTIVITY_IMPORT_FAILED]: activityImportFailedDataSchema,
  [ITINERARY_SAVED]: itinerarySavedDataSchema,
  [ITINERARY_DELETED]: itineraryDeletedDataSchema,
  [COMMENT_CREATED]: commentEventDataSchema,
  [COMMENT_UPDATED]: commentEventDataSchema,
  [COMMENT_DELETED]: commentEventDataSchema,
  [KUDOS_CHANGED]: kudosChangedDataSchema,
} as const satisfies Record<MobileEventType, z.ZodType>;

export type MobileEventData =
  | ActivityProcessedData
  | ActivityFailedData
  | ActivitySegmentsMatchedData
  | ActivityUpdatedData
  | ActivityDeletedData
  | ActivityImportCompletedData
  | ActivityImportFailedData
  | ItinerarySavedData
  | ItineraryDeletedData
  | CommentEventData
  | KudosChangedData;

/** Data payload type for a given mobile event type, e.g. `MobileEventDataFor<typeof ACTIVITY_PROCESSED>`. */
export type MobileEventDataFor<T extends MobileEventType> = z.infer<
  (typeof mobileEventDataSchemas)[T]
>;
