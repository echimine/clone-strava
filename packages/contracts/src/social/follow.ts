import { z } from "zod";
import { feedAuthorSchema } from "../activities/feed.js";

/**
 * The viewer's relation to an athlete (ADR-036 §1): `none`, a `pending`
 * request, or an `accepted` follow. Lists use `null` for the viewer themself.
 */
export const viewerFollowStatusSchema = z.enum(["none", "pending", "accepted"]);
export type ViewerFollowStatus = z.infer<typeof viewerFollowStatusSchema>;

/** `PUT` / `DELETE /v1/athletes/:id/follow` response (ADR-036 §1). */
export const followResponseSchema = z.object({
  athleteId: z.uuid(),
  viewerFollowStatus: viewerFollowStatusSchema,
  /** The athlete's accepted followers, after the change. */
  followerCount: z.number().int().nonnegative(),
});
export type FollowResponse = z.infer<typeof followResponseSchema>;

/**
 * Query of every follow list (ADR-036 §1): `cursor` is the opaque
 * `nextCursor` of the previous page.
 */
export const listFollowsQuerySchema = z.object({
  cursor: z.string().min(1).max(200).optional(),
  limit: z.coerce.number().int().min(1).max(50).default(20),
});
export type ListFollowsQuery = z.infer<typeof listFollowsQuerySchema>;

/** One athlete of a followers or following list, with the viewer's relation to them (`null`: the viewer). */
export const followListItemSchema = z.object({
  athlete: feedAuthorSchema,
  viewerFollowStatus: viewerFollowStatusSchema.nullable(),
});
export type FollowListItem = z.infer<typeof followListItemSchema>;

/** `GET /v1/athletes/:id/followers` and `/following`: most recent first; `nextCursor` null on the last page. */
export const followListResponseSchema = z.object({
  items: z.array(followListItemSchema),
  nextCursor: z.string().min(1).nullable(),
});
export type FollowListResponse = z.infer<typeof followListResponseSchema>;

/** One incoming follow request: who asked, and when. */
export const followRequestItemSchema = followListItemSchema.extend({
  requestedAt: z.iso.datetime(),
});
export type FollowRequestItem = z.infer<typeof followRequestItemSchema>;

/** `GET /v1/me/follow-requests`: incoming `pending` follows, most recent first. */
export const followRequestListResponseSchema = z.object({
  items: z.array(followRequestItemSchema),
  nextCursor: z.string().min(1).nullable(),
});
export type FollowRequestListResponse = z.infer<typeof followRequestListResponseSchema>;

/**
 * `PUT /v1/me/follow-settings` body and response (ADR-036 §1): "Approuver
 * mes abonnés". Turning it off accepts every pending request.
 */
export const followSettingsSchema = z.object({
  approveFollowers: z.boolean(),
});
export type FollowSettings = z.infer<typeof followSettingsSchema>;
