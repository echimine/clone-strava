import { z } from "zod";

/**
 * The backoffice dashboard (ADR-038 §15): two bands computed on the fly from our database only
 * (app usage stays in PostHog). Administrators and `sandbox` subscriptions are left out; banned
 * athletes stay counted. Read only: nothing is written to the Journal.
 */

/** `GET /v1/admin/stats/todo`: the work waiting now ("À traiter"). */
export const adminTodoStatsSchema = z.object({
  /** Open Reports (cases) and when the oldest was opened; red past 24 h. */
  openReports: z.object({
    count: z.number().int(),
    oldestOpenedAt: z.iso.datetime().nullable(),
  }),
  /** Activities whose processing failed (`processing_status = failed`). */
  failedActivities: z.number().int(),
  /** Imports that failed in the last 7 days. */
  failedImports: z.number().int(),
  /** Failed jobs, all queues together. */
  failedJobs: z.number().int(),
  /** Efforts to review (`segment_effort.status = suspicious`). */
  suspiciousEfforts: z.number().int(),
});
export type AdminTodoStats = z.infer<typeof adminTodoStatsSchema>;

/** The Growth band's period: the last 7, 30 or 90 Paris days, today included. */
export const ADMIN_STATS_PERIODS = ["7d", "30d", "90d"] as const;
export const adminStatsPeriodSchema = z.enum(ADMIN_STATS_PERIODS);
export type AdminStatsPeriod = z.infer<typeof adminStatsPeriodSchema>;
export const ADMIN_DEFAULT_STATS_PERIOD: AdminStatsPeriod = "30d";

/** `?period=7d|30d|90d`, 30 days by default. */
export const adminGrowthQuerySchema = z.object({
  period: adminStatsPeriodSchema.default(ADMIN_DEFAULT_STATS_PERIOD),
});
export type AdminGrowthQuery = z.infer<typeof adminGrowthQuerySchema>;

/** A count over the period and over the previous period of the same length. */
export const adminTrendSchema = z.object({
  value: z.number().int(),
  previous: z.number().int(),
});
export type AdminTrend = z.infer<typeof adminTrendSchema>;

/** `GET /v1/admin/stats/growth`: the "Croissance" band and its daily chart. */
export const adminGrowthStatsSchema = z.object({
  period: adminStatsPeriodSchema,
  /** First and last Paris day of the period (both included). */
  from: z.iso.date(),
  to: z.iso.date(),
  signUps: adminTrendSchema,
  /** Athletes with at least one Activity started in the period. */
  activeAthletes: adminTrendSchema,
  /** Activities by `started_at`, never `created_at`. */
  activities: z.object({
    total: adminTrendSchema,
    recorded: adminTrendSchema,
    imported: adminTrendSchema,
    manual: adminTrendSchema,
  }),
  premium: z.object({
    /** Paying subscriptions active now. */
    payingActive: z.number().int(),
    /** Trials running now. */
    trialsActive: z.number().int(),
    /** Promotional Premium ("Premium offert") active now. */
    promotionalActive: z.number().int(),
    trialsStarted: adminTrendSchema,
    newPaying: adminTrendSchema,
  }),
  engagement: z.object({
    kudos: adminTrendSchema,
    comments: adminTrendSchema,
    follows: adminTrendSchema,
    media: adminTrendSchema,
  }),
  /** One point per Paris day of the period, oldest first. */
  daily: z.array(
    z.object({
      day: z.iso.date(),
      signUps: z.number().int(),
      activities: z.number().int(),
    }),
  ),
});
export type AdminGrowthStats = z.infer<typeof adminGrowthStatsSchema>;
