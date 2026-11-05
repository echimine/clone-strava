import { z } from "zod";
import { feedAuthorSchema } from "../activities/feed.js";
import { visibilitySchema } from "../common/enums.js";
import { sportTypeCodeSchema } from "../sports/sport-type.js";

/**
 * A Segment's sheet and Leaderboard (ADR-039 §8, §9, §12): `GET /v1/segments/:id` and
 * `GET /v1/segments/:id/leaderboard`.
 */

/** ADR-039 §5: climb category, `null` under a score of 8,000. */
export const segmentClimbCategorySchema = z.enum(["hc", "1", "2", "3", "4"]);

/** ADR-039 §8: an Effort's personal Medal (« PR », « 2 », « 3 »). */
export const segmentMedalSchema = z.enum(["gold", "silver", "bronze"]);
export type SegmentMedal = z.infer<typeof segmentMedalSchema>;

/** ADR-039 §8: the sex selector; anything but `all` is Premium. */
export const leaderboardGenderSchema = z.enum(["all", "male", "female"]);
export type LeaderboardGender = z.infer<typeof leaderboardGenderSchema>;

/** ADR-039 §8: the one other filter, combined with the sex selector. */
export const leaderboardFilterSchema = z.enum(["period", "following", "age", "weight"]);
export type LeaderboardFilter = z.infer<typeof leaderboardFilterSchema>;

/** `filter=period` values: a calendar period in the viewer's time zone, the week from Monday. */
export const LEADERBOARD_PERIODS = ["today", "week", "month", "year"] as const;
/** `filter=age` values, from the current birth date. */
export const LEADERBOARD_AGE_BANDS = ["0-19", "20-24", "25-34", "35-44", "45-54", "55-64", "65-69", "70-74", "75+"] as const;
/** `filter=weight` values in kg, from the current weight. */
export const LEADERBOARD_WEIGHT_BANDS = ["0-54", "55-64", "65-74", "75-84", "85-94", "95-104", "105-114", "115+"] as const;

/** Lines per Premium page (ADR-039 §12); without Premium, the top 10 only. */
export const LEADERBOARD_PAGE_SIZE = 50;
export const LEADERBOARD_FREE_SIZE = 10;

/**
 * `GET /v1/segments/:id/leaderboard` query. `value` goes with `filter` (a period, an age or a
 * weight band; none for `following`); `tz` is the viewer's IANA time zone for `period` (else the
 * `x-time-zone` header, else UTC). A mismatch answers `422 invalid_leaderboard_filter`.
 */
export const leaderboardQuerySchema = z.object({
  gender: leaderboardGenderSchema.default("all"),
  filter: leaderboardFilterSchema.optional(),
  value: z.string().min(1).max(20).optional(),
  tz: z.string().min(1).max(64).optional(),
  cursor: z.string().min(1).max(200).optional(),
});
export type LeaderboardQuery = z.infer<typeof leaderboardQuerySchema>;

/** One line: an athlete's best Effort that stands, ranked for the viewer (ties share the rank). */
export const leaderboardEntrySchema = z.object({
  rank: z.number().int().positive(),
  athlete: feedAuthorSchema,
  effortId: z.uuid(),
  activityId: z.uuid(),
  elapsedTimeS: z.number().int().nonnegative(),
  startedAt: z.iso.datetime(),
});
export type LeaderboardEntry = z.infer<typeof leaderboardEntrySchema>;

/**
 * ADR-039 §8: the Local Legend for the sex selector (`null` when nobody has an Effort that stands
 * over the last 90 days), and the viewer's own count over the same 90 days (Tous).
 */
export const localLegendSchema = z.object({
  legend: z
    .object({
      athlete: feedAuthorSchema,
      effortCount: z.number().int().positive(),
    })
    .nullable(),
  myEffortCount: z.number().int().nonnegative(),
});
export type LocalLegend = z.infer<typeof localLegendSchema>;

/**
 * `GET /v1/segments/:id/leaderboard` response. `limited`: without Premium, `entries` is the top 10
 * of Tous. `me` is the viewer's line in this filter, `null` when they are not in it.
 * `athleteCount`: athletes with an Effort that stands on the Segment (Tous, not filtered by Blocks
 * and Bans). `nextCursor` only with Premium.
 */
export const leaderboardResponseSchema = z.object({
  limited: z.boolean(),
  entries: z.array(leaderboardEntrySchema),
  me: leaderboardEntrySchema.nullable(),
  localLegend: localLegendSchema,
  athleteCount: z.number().int().nonnegative(),
  nextCursor: z.string().nullable(),
});
export type LeaderboardResponse = z.infer<typeof leaderboardResponseSchema>;

/** One of the viewer's Efforts on the sheet, whatever the visibility of its Activity. */
export const mySegmentEffortSchema = z.object({
  id: z.uuid(),
  activityId: z.uuid(),
  activityVisibility: visibilitySchema,
  startedAt: z.iso.datetime(),
  elapsedTimeS: z.number().int().nonnegative(),
  medal: segmentMedalSchema.nullable(),
  /** False: « Privée · hors Classement » (not public, in the privacy zone, or rejected). */
  standing: z.boolean(),
  /** The Effort that forms the viewer's line in Tous; only it carries `rank`. */
  isLeaderboardLine: z.boolean(),
  rank: z.number().int().positive().nullable(),
});
export type MySegmentEffort = z.infer<typeof mySegmentEffortSchema>;

/** `GET /v1/segments/:id` (ADR-039 §12): free; `404 segment_not_found` once deleted. */
export const segmentSheetSchema = z.object({
  id: z.uuid(),
  name: z.string(),
  sportTypeCode: sportTypeCodeSchema,
  verified: z.boolean(),
  distanceM: z.number().nonnegative(),
  elevationGainM: z.number().nonnegative().nullable(),
  avgGrade: z.number().nullable(),
  maxGrade: z.number().nullable(),
  climbCategory: segmentClimbCategorySchema.nullable(),
  /** The path every point, as polyline6, and its altitudes in meters, one per point. */
  track: z.object({
    polyline6: z.string(),
    altitudesM: z.array(z.number()),
  }),
  starred: z.boolean(),
  favoriteCount: z.number().int().nonnegative(),
  isMine: z.boolean(),
  /** The creator may delete it while nobody else has an Effort on it. */
  canDelete: z.boolean(),
  /** The retro-matching of a new Segment is still running (« Recherche des Efforts passés… »). */
  historyMatching: z.boolean(),
  /** Every Effort of the viewer, newest first. */
  myEfforts: z.array(mySegmentEffortSchema),
  /** The viewer's best Effort that is not rejected, whatever the visibility; `null` without one. */
  myRecord: mySegmentEffortSchema.nullable(),
  localLegend: localLegendSchema,
  /** The top 10 of Tous and the viewer's line (`limited` is always true here). */
  leaderboard: leaderboardResponseSchema,
});
export type SegmentSheet = z.infer<typeof segmentSheetSchema>;
