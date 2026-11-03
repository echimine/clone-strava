import { z } from "zod";
import { feedAuthorSchema } from "../activities/feed.js";
import { viewerFollowStatusSchema } from "../social/follow.js";
import { sportTypeCodeSchema } from "../sports/sport-type.js";

/**
 * `GET /v1/athletes/:id` response (ADR-036 §3). Every figure covers only the Activities the viewer
 * may see. The last three fields are present only on the viewer's own profile.
 */
export const athleteProfileResponseSchema = z.object({
  athlete: feedAuthorSchema,
  activityCount: z.number().int().nonnegative(),
  /** Consecutive weeks (Monday to Sunday, `Europe/Paris`) with an Activity, all sports (ADR-036 §4). */
  streakWeeks: z.number().int().nonnegative(),
  followerCount: z.number().int().nonnegative(),
  followingCount: z.number().int().nonnegative(),
  /** `null` on the viewer's own profile. */
  viewerFollowStatus: viewerFollowStatusSchema.nullable(),
  /** Up to 2 accepted followers of the athlete whom the viewer follows, most recent first. */
  followersYouKnow: z.array(feedAuthorSchema).max(2),
  /** Practiced sports in their order, then the other sports of visible Activities by count. */
  practicedSports: z.array(sportTypeCodeSchema),
  approveFollowers: z.boolean().optional(),
  pendingFollowRequestCount: z.number().int().nonnegative().optional(),
  itineraryCount: z.number().int().nonnegative().optional(),
});
export type AthleteProfileResponse = z.infer<typeof athleteProfileResponseSchema>;

const nameSchema = z.string().trim().min(1).max(50);

/** `PATCH /v1/me/profile` body (ADR-036 §3): each name trimmed, 1–50 characters. */
export const updateProfileRequestSchema = z.object({
  firstName: nameSchema,
  lastName: nameSchema,
});
export type UpdateProfileRequest = z.infer<typeof updateProfileRequestSchema>;

/** `PATCH /v1/me/profile` response: the athlete's identity as everyone now sees it. */
export const updateProfileResponseSchema = z.object({
  athlete: feedAuthorSchema,
});
export type UpdateProfileResponse = z.infer<typeof updateProfileResponseSchema>;
