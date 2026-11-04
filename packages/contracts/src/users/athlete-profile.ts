import { z } from "zod";
import { feedAuthorSchema } from "../activities/feed.js";
import { viewerFollowStatusSchema } from "../social/follow.js";
import { sportTypeCodeSchema } from "../sports/sport-type.js";
import { genderSchema } from "./onboarding-answers.js";

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

/** Bio and Ville: trimmed; an empty string clears the field. */
export const PROFILE_BIO_MAX_LENGTH = 300;
export const PROFILE_CITY_MAX_LENGTH = 100;
/** Poids (kg) accepted by "Modifier le profil". */
export const PROFILE_WEIGHT_KG_RANGE = { min: 20, max: 300 } as const;

/**
 * `PATCH /v1/me/profile` body (ADR-036 §3): each name trimmed, 1–50 characters. Every other field
 * is optional: absent leaves it unchanged. `bio`, `city` and `country` are cleared by `""`.
 * `country` is an ISO 3166-1 alpha-2 code. `mainSportCode` becomes the first Practiced sport.
 * `birthDate` keeps the Onboarding's minimum age (ADR-035 §5).
 */
export const updateProfileRequestSchema = z.object({
  firstName: nameSchema,
  lastName: nameSchema,
  bio: z.string().trim().max(PROFILE_BIO_MAX_LENGTH).optional(),
  city: z.string().trim().max(PROFILE_CITY_MAX_LENGTH).optional(),
  country: z
    .string()
    .trim()
    .regex(/^(?:[A-Z]{2})?$/, "ISO 3166-1 alpha-2 code")
    .optional(),
  mainSportCode: sportTypeCodeSchema.optional(),
  /** `YYYY-MM-DD`. */
  birthDate: z.iso.date().optional(),
  gender: genderSchema.optional(),
  weightKg: z.number().min(PROFILE_WEIGHT_KG_RANGE.min).max(PROFILE_WEIGHT_KG_RANGE.max).optional(),
});
export type UpdateProfileRequest = z.infer<typeof updateProfileRequestSchema>;

/** `PATCH /v1/me/profile` response: the athlete's identity as everyone now sees it. */
export const updateProfileResponseSchema = z.object({
  athlete: feedAuthorSchema,
});
export type UpdateProfileResponse = z.infer<typeof updateProfileResponseSchema>;

/** What "Modifier le profil" shows (ADR-036 §3); `null` = never filled. */
export const editableProfileSchema = z.object({
  firstName: z.string().nullable(),
  lastName: z.string().nullable(),
  bio: z.string().nullable(),
  city: z.string().nullable(),
  /** ISO 3166-1 alpha-2 code. */
  country: z.string().nullable(),
  /** The first Practiced sport. */
  mainSportCode: sportTypeCodeSchema.nullable(),
  /** `YYYY-MM-DD`. */
  birthDate: z.string().nullable(),
  gender: genderSchema.nullable(),
  weightKg: z.number().nullable(),
});
export type EditableProfile = z.infer<typeof editableProfileSchema>;

/**
 * `GET /v1/me/profile` response. Nested: @nestjs/swagger reads a top-level nullable as an array.
 */
export const editableProfileResponseSchema = z.object({
  profile: editableProfileSchema,
});
export type EditableProfileResponse = z.infer<typeof editableProfileResponseSchema>;
