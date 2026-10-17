import { z } from "zod";
import { feedAuthorSchema } from "../activities/feed.js";

/**
 * `GET /v1/activities/:id/kudos` query (ADR-034 §1): `cursor` is the
 * opaque `nextCursor` of the previous page.
 */
export const listKudosQuerySchema = z.object({
  cursor: z.string().min(1).max(200).optional(),
  limit: z.coerce.number().int().min(1).max(50).default(20),
});
export type ListKudosQuery = z.infer<typeof listKudosQuerySchema>;

/** One kudos of an Activity: who gave it and when (ADR-034 §1). */
export const kudosListItemSchema = z.object({
  athlete: feedAuthorSchema,
  givenAt: z.iso.datetime(),
});
export type KudosListItem = z.infer<typeof kudosListItemSchema>;

/** A page of kudos, most recent first; `nextCursor` is null on the last page. */
export const listKudosResponseSchema = z.object({
  items: z.array(kudosListItemSchema),
  nextCursor: z.string().min(1).nullable(),
});
export type ListKudosResponse = z.infer<typeof listKudosResponseSchema>;
