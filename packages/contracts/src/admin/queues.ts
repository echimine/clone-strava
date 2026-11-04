import { z } from "zod";
import {
  ACTIVITIES_QUEUE_NAME,
  IMPORT_ACTIVITY_JOB_NAME,
  IMPORTS_QUEUE_NAME,
  PROCESS_ACTIVITY_JOB_NAME,
} from "../activities/jobs.js";
import { BUCKET_SWEEP_QUEUE_NAME } from "../common/bucket-sweep.js";
import { SEGMENTS_QUEUE_NAME } from "../segments/jobs.js";
import { SUBSCRIPTIONS_QUEUE_NAME } from "../subscriptions/jobs.js";
import { AVATARS_QUEUE_NAME } from "../users/avatar-jobs.js";
import { adminListResponseSchema, adminPageQuerySchema } from "./list.js";

/**
 * The queues the backoffice reads and drives through `/v1/admin/queues/*` (ADR-038 §14), and
 * no other. A queue no job has used yet (no key in Redis) reads as empty.
 */
export const ADMIN_QUEUE_NAMES = [
  ACTIVITIES_QUEUE_NAME,
  IMPORTS_QUEUE_NAME,
  SEGMENTS_QUEUE_NAME,
  SUBSCRIPTIONS_QUEUE_NAME,
  AVATARS_QUEUE_NAME,
  BUCKET_SWEEP_QUEUE_NAME,
  // Account deletion (ADR-038 §13): replace by its `ACCOUNTS_QUEUE_NAME` once declared (#214).
  "accounts",
  // Sanction e-mails (ADR-038 §4): replace by its `EMAILS_QUEUE_NAME` once declared (#218).
  "emails",
] as const;
export const adminQueueNameSchema = z.enum(ADMIN_QUEUE_NAMES);
export type AdminQueueName = z.infer<typeof adminQueueNameSchema>;

/**
 * Jobs a raw retry would not relaunch (ADR-038 §14): they do nothing unless their Activity or
 * import is `processing`, so the backoffice offers « Retraiter » (`Échecs` tab) instead and
 * the API answers `409 retry_refused`.
 */
export const ADMIN_RETRY_REFUSED_JOB_NAMES: readonly string[] = [PROCESS_ACTIVITY_JOB_NAME, IMPORT_ACTIVITY_JOB_NAME];

/** Jobs of a queue by state (`getJobCounts`). */
export const adminQueueCountsSchema = z.object({
  waiting: z.number().int().nonnegative(),
  active: z.number().int().nonnegative(),
  delayed: z.number().int().nonnegative(),
  prioritized: z.number().int().nonnegative(),
  waitingChildren: z.number().int().nonnegative(),
  completed: z.number().int().nonnegative(),
  failed: z.number().int().nonnegative(),
});
export type AdminQueueCounts = z.infer<typeof adminQueueCountsSchema>;

/** A job scheduler of a queue (`reconcile-activities`, `bucket-sweep`): rhythm and next run. */
export const adminQueueSchedulerSchema = z.object({
  id: z.string(),
  jobName: z.string(),
  /** Interval in milliseconds, for an `every` scheduler. */
  everyMs: z.number().int().positive().nullable(),
  /** Cron pattern, for a `pattern` scheduler. */
  pattern: z.string().nullable(),
  timeZone: z.string().nullable(),
  nextRunAt: z.iso.datetime().nullable(),
});
export type AdminQueueScheduler = z.infer<typeof adminQueueSchedulerSchema>;

export const adminQueueSchema = z.object({
  name: adminQueueNameSchema,
  isPaused: z.boolean(),
  counts: adminQueueCountsSchema,
  schedulers: z.array(adminQueueSchedulerSchema),
});
export type AdminQueue = z.infer<typeof adminQueueSchema>;

/** `GET /v1/admin/queues`: every whitelisted queue, in the whitelist's order. */
export const adminQueueListResponseSchema = z.object({ items: z.array(adminQueueSchema) });
export type AdminQueueListResponse = z.infer<typeof adminQueueListResponseSchema>;

/** The states whose jobs `GET /v1/admin/queues/:name/jobs` lists. */
export const adminQueueJobStateSchema = z.enum(["failed", "completed", "active", "waiting", "delayed"]);
export type AdminQueueJobState = z.infer<typeof adminQueueJobStateSchema>;

/** `GET /v1/admin/queues/:name/jobs?state=failed&page&pageSize`, newest first. */
export const adminQueueJobListQuerySchema = adminPageQuerySchema.extend({
  state: adminQueueJobStateSchema.default("failed"),
});
export type AdminQueueJobListQuery = z.infer<typeof adminQueueJobListQuerySchema>;

/** One job of a queue. */
export const adminQueueJobSchema = z.object({
  id: z.string(),
  name: z.string(),
  queue: adminQueueNameSchema,
  /** Why its last attempt failed, if it did. */
  failedReason: z.string().nullable(),
  attemptsMade: z.number().int().nonnegative(),
  maxAttempts: z.number().int().positive(),
  createdAt: z.iso.datetime(),
  processedAt: z.iso.datetime().nullable(),
  finishedAt: z.iso.datetime().nullable(),
  /** A raw retry is refused: the backoffice points to « Retraiter » instead. */
  retryRefused: z.boolean(),
});
export type AdminQueueJob = z.infer<typeof adminQueueJobSchema>;

export const adminQueueJobListResponseSchema = adminListResponseSchema(adminQueueJobSchema);
export type AdminQueueJobListResponse = z.infer<typeof adminQueueJobListResponseSchema>;

/**
 * `GET /v1/admin/queues/:name/jobs/:id`: the job, its stack traces (newest last) and its data,
 * read-only, with the Activity and athlete its data names, for links.
 */
export const adminQueueJobDetailSchema = adminQueueJobSchema.extend({
  state: z.string(),
  stacktrace: z.array(z.string()),
  data: z.unknown(),
  activityId: z.uuid().nullable(),
  userId: z.uuid().nullable(),
});
export type AdminQueueJobDetail = z.infer<typeof adminQueueJobDetailSchema>;

/** `POST /v1/admin/queues/:name/retry-failed`: failed jobs relaunched, and refused ones left. */
export const adminQueueRetryFailedResponseSchema = z.object({
  retried: z.number().int().nonnegative(),
  refused: z.number().int().nonnegative(),
});
export type AdminQueueRetryFailedResponse = z.infer<typeof adminQueueRetryFailedResponseSchema>;
