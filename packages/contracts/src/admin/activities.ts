import { z } from "zod";
import { activityStatsSchema } from "../activities/activity.js";
import { feedAuthorSchema } from "../activities/feed.js";
import { activityImportSchema } from "../activities/import.js";
import { mediaSchema } from "../activities/media.js";
import {
  activitySourceSchema,
  processingStatusSchema,
  visibilitySchema,
} from "../common/enums.js";
import {
  adminListQuerySchema,
  adminListResponseSchema,
  adminPeriodShape,
  isOrderedPeriod,
  periodOrderIssue,
} from "./list.js";

/**
 * `GET /v1/admin/activities?q&status&source&sportTypeCode&visibility&userId&from&to&page&pageSize`
 * (ADR-038 §11): every Activity, private ones included, newest created first. `q` searches the
 * title and the athlete's name or e-mail; `from`/`to` are Paris days of `started_at`; `userId`
 * is what "Voir ses Activités" of a user sheet pre-fills.
 */
export const adminActivityListQuerySchema = adminListQuerySchema
  .extend({
    status: processingStatusSchema.optional(),
    source: activitySourceSchema.optional(),
    sportTypeCode: z.string().trim().min(1).max(64).optional(),
    visibility: visibilitySchema.optional(),
    userId: z.uuid().optional(),
    ...adminPeriodShape,
  })
  .refine(isOrderedPeriod, periodOrderIssue);
export type AdminActivityListQuery = z.infer<typeof adminActivityListQuerySchema>;

/** One row of the backoffice Activities list. */
export const adminActivityListItemSchema = z.object({
  id: z.uuid(),
  title: z.string(),
  athlete: feedAuthorSchema,
  sportTypeCode: z.string(),
  processingStatus: processingStatusSchema,
  source: activitySourceSchema,
  visibility: visibilitySchema,
  startedAt: z.iso.datetime(),
  createdAt: z.iso.datetime(),
  /** Official distance once processed. */
  distanceM: z.number().nullable(),
});
export type AdminActivityListItem = z.infer<typeof adminActivityListItemSchema>;

export const adminActivityListResponseSchema = adminListResponseSchema(adminActivityListItemSchema);
export type AdminActivityListResponse = z.infer<typeof adminActivityListResponseSchema>;

/** A comment as the backoffice shows it: author, text, date (ADR-038 §11). */
export const adminActivityCommentSchema = z.object({
  id: z.uuid(),
  author: feedAuthorSchema,
  body: z.string(),
  createdAt: z.iso.datetime(),
  updatedAt: z.iso.datetime().nullable(),
});
export type AdminActivityComment = z.infer<typeof adminActivityCommentSchema>;

export const adminActivityKudosSchema = z.object({
  athlete: feedAuthorSchema,
  createdAt: z.iso.datetime(),
});
export type AdminActivityKudos = z.infer<typeof adminActivityKudosSchema>;

/** An effort on a Segment, read-only (ADR-038 §11). */
export const adminSegmentEffortSchema = z.object({
  id: z.uuid(),
  segmentId: z.uuid(),
  segmentName: z.string(),
  elapsedTimeS: z.number().int(),
  startedAt: z.iso.datetime(),
  rank: z.number().int().nullable(),
});
export type AdminSegmentEffort = z.infer<typeof adminSegmentEffortSchema>;

/** The most comments and kudos the detail lists, newest first; the counts are the totals. */
export const ADMIN_ACTIVITY_DETAIL_LIST_LIMIT = 200;

/**
 * `GET /v1/admin/activities/:id` (ADR-038 §11): official values, status with the worker's error
 * and attempts, the **public** trace only (`activity_track.route`, already cut by the privacy
 * zone; never the raw trace nor the imported file), Media, comments, kudos, the linked import
 * and the Segment efforts.
 */
export const adminActivityDetailSchema = z.object({
  id: z.uuid(),
  title: z.string(),
  description: z.string().nullable(),
  athlete: feedAuthorSchema,
  sportTypeCode: z.string(),
  visibility: visibilitySchema,
  source: activitySourceSchema,
  processingStatus: processingStatusSchema,
  /** The worker's raw error code, kept until a successful run. */
  processingError: z.string().nullable(),
  processingAttempts: z.number().int().nonnegative(),
  startedAt: z.iso.datetime(),
  endedAt: z.iso.datetime(),
  createdAt: z.iso.datetime(),
  updatedAt: z.iso.datetime(),
  processedAt: z.iso.datetime().nullable(),
  stats: activityStatsSchema.nullable(),
  /**
   * The public trace as `[longitude, latitude]` pairs; null without one. An array of length 2
   * rather than `z.tuple`: a tuple exports as `prefixItems`, which swift-openapi-generator rejects.
   */
  route: z.array(z.array(z.number()).length(2)).nullable(),
  locationName: z.string().nullable(),
  media: z.array(mediaSchema),
  comments: z.array(adminActivityCommentSchema),
  commentCount: z.number().int().nonnegative(),
  kudos: z.array(adminActivityKudosSchema),
  kudosCount: z.number().int().nonnegative(),
  /** The import this Activity came from, if any. */
  import: activityImportSchema.nullable(),
  efforts: z.array(adminSegmentEffortSchema),
});
export type AdminActivityDetail = z.infer<typeof adminActivityDetailSchema>;

/** `POST /v1/admin/activities/:id/reprocess` → `202` (ADR-038 §11): back to `processing`. */
export const adminActivityReprocessResponseSchema = z.object({
  id: z.uuid(),
  processingStatus: processingStatusSchema,
});
export type AdminActivityReprocessResponse = z.infer<typeof adminActivityReprocessResponseSchema>;

/** `POST /v1/admin/activities/:id/reset-text` → `200`: the default title, no description. */
export const adminActivityTextResponseSchema = z.object({
  id: z.uuid(),
  title: z.string(),
  description: z.string().nullable(),
});
export type AdminActivityTextResponse = z.infer<typeof adminActivityTextResponseSchema>;
