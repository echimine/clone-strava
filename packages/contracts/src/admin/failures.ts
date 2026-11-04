import { z } from "zod";
import { feedAuthorSchema } from "../activities/feed.js";
import { activityImportErrorCodeSchema } from "../activities/import.js";
import { activityImportFormatSchema } from "../common/enums.js";
import { adminListResponseSchema, adminPageQuerySchema } from "./list.js";

/**
 * The "Échecs" tab of the Jobs screen (ADR-038 §14): failed Activities, failed imports and
 * failed recomputations, each a paginated list, newest first, whose `total` is what « Retraiter
 * les N en échec » relaunches (at most {@link ADMIN_BATCH_MAX} per click).
 */
export const adminFailureListQuerySchema = adminPageQuerySchema;
export type AdminFailureListQuery = z.infer<typeof adminFailureListQuerySchema>;

/** The most a batch relaunches per click (ADR-038 §14). */
export const ADMIN_BATCH_MAX = 500;

/** `GET /v1/admin/failures/activities`: `failed` Activities with the worker's error. */
export const adminFailedActivitySchema = z.object({
  id: z.uuid(),
  title: z.string(),
  athlete: feedAuthorSchema,
  sportTypeCode: z.string(),
  /** The worker's raw error code. */
  processingError: z.string().nullable(),
  processingAttempts: z.number().int().nonnegative(),
  startedAt: z.iso.datetime(),
  createdAt: z.iso.datetime(),
});
export type AdminFailedActivity = z.infer<typeof adminFailedActivitySchema>;
export const adminFailedActivityListResponseSchema = adminListResponseSchema(adminFailedActivitySchema);
export type AdminFailedActivityListResponse = z.infer<typeof adminFailedActivityListResponseSchema>;

/** `GET /v1/admin/failures/imports`: `failed` file imports. */
export const adminFailedImportSchema = z.object({
  id: z.uuid(),
  athlete: feedAuthorSchema,
  format: activityImportFormatSchema,
  fileName: z.string(),
  error: activityImportErrorCodeSchema.nullable(),
  attempts: z.number().int().nonnegative(),
  createdAt: z.iso.datetime(),
  processedAt: z.iso.datetime().nullable(),
});
export type AdminFailedImport = z.infer<typeof adminFailedImportSchema>;
export const adminFailedImportListResponseSchema = adminListResponseSchema(adminFailedImportSchema);
export type AdminFailedImportListResponse = z.infer<typeof adminFailedImportListResponseSchema>;

/**
 * `GET /v1/admin/failures/recomputes`: processed Activities whose official values were computed
 * for another sport than theirs (ADR-033 §5), i.e. whose `reprocess-activity` failed.
 */
export const adminStaleActivitySchema = z.object({
  id: z.uuid(),
  title: z.string(),
  athlete: feedAuthorSchema,
  sportTypeCode: z.string(),
  /** The sport the official values were computed for. */
  computedForSportTypeCode: z.string().nullable(),
  startedAt: z.iso.datetime(),
  updatedAt: z.iso.datetime(),
});
export type AdminStaleActivity = z.infer<typeof adminStaleActivitySchema>;
export const adminStaleActivityListResponseSchema = adminListResponseSchema(adminStaleActivitySchema);
export type AdminStaleActivityListResponse = z.infer<typeof adminStaleActivityListResponseSchema>;

/**
 * `POST /v1/admin/activities/reprocess-failed`, `…/recompute-stale` and
 * `/v1/admin/activity-imports/reprocess-failed` → `202`: how many were relaunched.
 */
export const adminBatchResponseSchema = z.object({
  relaunched: z.number().int().nonnegative(),
});
export type AdminBatchResponse = z.infer<typeof adminBatchResponseSchema>;

/** `POST /v1/admin/activities/:id/recompute` → `202`. */
export const adminActivityRecomputeResponseSchema = z.object({
  id: z.uuid(),
  jobId: z.string(),
});
export type AdminActivityRecomputeResponse = z.infer<typeof adminActivityRecomputeResponseSchema>;
