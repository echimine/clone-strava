import { z } from "zod";
import { feedAuthorSchema } from "../activities/feed.js";
import { viewerFollowStatusSchema } from "../social/follow.js";

/**
 * `GET /v1/athletes/search` query (ADR-036 §2). `q` is trimmed and must
 * then hold 2 to 50 characters, otherwise `422 invalid_query` (checked by
 * `UsersService.searchByName`, not here, so the code is specific).
 */
export const athleteSearchQuerySchema = z.object({
  q: z.string().optional(),
});
export type AthleteSearchQuery = z.infer<typeof athleteSearchQuerySchema>;

/** One athlete found, with the viewer's relation to them (never the viewer themself). */
export const athleteSearchItemSchema = z.object({
  athlete: feedAuthorSchema,
  viewerFollowStatus: viewerFollowStatusSchema,
});
export type AthleteSearchItem = z.infer<typeof athleteSearchItemSchema>;

/** At most 20 athletes, word-start matches first, then alphabetical; no pagination ("refine your search"). */
export const athleteSearchResponseSchema = z.object({
  items: z.array(athleteSearchItemSchema),
});
export type AthleteSearchResponse = z.infer<typeof athleteSearchResponseSchema>;
