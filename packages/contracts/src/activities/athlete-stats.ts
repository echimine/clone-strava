import { z } from "zod";
import { sportTypeCodeSchema } from "../sports/sport-type.js";

/**
 * Weeks run Monday to Sunday in `Europe/Paris` (ADR-036 §4). Dates are calendar dates
 * `YYYY-MM-DD` in that time zone; a week is named by its Monday.
 */

/** `GET /v1/me/progress` query: an active sport is required. */
export const progressQuerySchema = z.object({
  sport: sportTypeCodeSchema.max(50),
});
export type ProgressQuery = z.infer<typeof progressQuerySchema>;

/** One week of the Progrès chart. */
export const progressWeekSchema = z.object({
  weekStart: z.iso.date(),
  distanceM: z.number().nonnegative(),
  elevationGainM: z.number().nonnegative(),
  movingTimeS: z.number().int().nonnegative(),
  activityCount: z.number().int().nonnegative(),
});
export type ProgressWeek = z.infer<typeof progressWeekSchema>;

/**
 * `GET /v1/me/progress` response (ADR-036 §4): the 12 weeks ending with the current one, oldest
 * first and zero-filled ("Cette semaine" is the last one), and the sport's Streak with the
 * current month's days that have an Activity of that sport.
 */
export const progressResponseSchema = z.object({
  sportTypeCode: sportTypeCodeSchema,
  weeks: z.array(progressWeekSchema),
  streak: z.object({
    weeks: z.number().int().nonnegative(),
    activeDays: z.array(z.iso.date()),
  }),
});
export type ProgressResponse = z.infer<typeof progressResponseSchema>;

/** `GET /v1/athletes/:id/stats` query: `sport` omitted means all sports. */
export const athleteStatsQuerySchema = z.object({
  sport: sportTypeCodeSchema.max(50).optional(),
});
export type AthleteStatsQuery = z.infer<typeof athleteStatsQuerySchema>;

/**
 * `GET /v1/athletes/:id/stats` response (ADR-036 §4), over the Activities the viewer may see.
 * `recent` averages the 4 full weeks before the current one; the year starts on 1 January.
 */
export const athleteStatsResponseSchema = z.object({
  // Optional rather than nullable (see `activityDetailSchema.description`): absent for all sports.
  sportTypeCode: sportTypeCodeSchema.optional(),
  recent: z.object({
    weeks: z.literal(4),
    activitiesPerWeek: z.number().nonnegative(),
    movingTimeSPerWeek: z.number().nonnegative(),
    distanceMPerWeek: z.number().nonnegative(),
  }),
  yearToDate: z.object({
    activityCount: z.number().int().nonnegative(),
    movingTimeS: z.number().int().nonnegative(),
    distanceM: z.number().nonnegative(),
    elevationGainM: z.number().nonnegative(),
  }),
  allTime: z.object({
    activityCount: z.number().int().nonnegative(),
    distanceM: z.number().nonnegative(),
    elevationGainM: z.number().nonnegative(),
  }),
});
export type AthleteStatsResponse = z.infer<typeof athleteStatsResponseSchema>;
