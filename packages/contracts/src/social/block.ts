import { z } from "zod";
import { feedAuthorSchema } from "../activities/feed.js";

/** One athlete the viewer blocked (ADR-038 §8), for Réglages > "Athlètes bloqués". */
export const blockedAthleteSchema = z.object({
  athlete: feedAuthorSchema,
  blockedAt: z.iso.datetime(),
});
export type BlockedAthlete = z.infer<typeof blockedAthleteSchema>;

/**
 * `GET /v1/me/blocks`: the athletes the viewer blocked, most recent first; never those who
 * blocked them. Not paginated: a Block list stays short.
 */
export const blockedAthleteListResponseSchema = z.object({
  items: z.array(blockedAthleteSchema),
});
export type BlockedAthleteListResponse = z.infer<typeof blockedAthleteListResponseSchema>;
