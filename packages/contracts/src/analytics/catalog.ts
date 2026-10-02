import { z } from "zod";

/**
 * Typed analytics event catalog (ADR-015 "Event naming and catalog"):
 * reliable, backend-emitted events only (`api`/`worker`, via `posthog-node`).
 * `object_action`, snake_case, past tense; no free-form strings in
 * application code.
 */
export const ANALYTICS_EVENTS = {
  ACTIVITY_PROCESSED: "activity_processed",
  ACTIVITY_FAILED: "activity_failed",
  ACTIVITY_IMPORTED: "activity_imported",
  ACTIVITY_IMPORT_FAILED: "activity_import_failed",
} as const;
export type AnalyticsEventName = (typeof ANALYTICS_EVENTS)[keyof typeof ANALYTICS_EVENTS];

/** No personal data (ADR-015 "Data sent"): sport type only, never GPS, route or photo. */
export const activityProcessedPropertiesSchema = z.object({
  sportTypeCode: z.string(),
});
export type ActivityProcessedProperties = z.infer<typeof activityProcessedPropertiesSchema>;

export const activityFailedPropertiesSchema = z.object({
  sportTypeCode: z.string().optional(),
  errorCode: z.string(),
});
export type ActivityFailedProperties = z.infer<typeof activityFailedPropertiesSchema>;

/** ADR-028 §4 step 11: file format and resolved sport, never the file name or content. */
export const activityImportedPropertiesSchema = z.object({
  format: z.string(),
  sportTypeCode: z.string(),
});
export type ActivityImportedProperties = z.infer<typeof activityImportedPropertiesSchema>;

export const activityImportFailedPropertiesSchema = z.object({
  format: z.string(),
  errorCode: z.string(),
});
export type ActivityImportFailedProperties = z.infer<typeof activityImportFailedPropertiesSchema>;

/** Payload schema for a given catalog event, keyed by its name. */
export const analyticsEventPropertiesSchemas = {
  [ANALYTICS_EVENTS.ACTIVITY_PROCESSED]: activityProcessedPropertiesSchema,
  [ANALYTICS_EVENTS.ACTIVITY_FAILED]: activityFailedPropertiesSchema,
  [ANALYTICS_EVENTS.ACTIVITY_IMPORTED]: activityImportedPropertiesSchema,
  [ANALYTICS_EVENTS.ACTIVITY_IMPORT_FAILED]: activityImportFailedPropertiesSchema,
} as const satisfies Record<AnalyticsEventName, z.ZodType>;
