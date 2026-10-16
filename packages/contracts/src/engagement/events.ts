import { z } from "zod";

/**
 * Domain events emitted by the `engagement` module after commit (ADR-034
 * §4, ADR-021 §3-5), IDs only. Never emitted for a replayed `POST` or a
 * repeated `DELETE` that wrote nothing. The realtime bridge relays them on
 * `activity:{activityId}` (ADR-034 §5).
 */
export const COMMENT_ADDED_EVENT = "engagement.comment.added";
export const COMMENT_EDITED_EVENT = "engagement.comment.edited";
export const COMMENT_DELETED_EVENT = "engagement.comment.deleted";

/** `userId` is the athlete who wrote the change (the deleter for a deletion). */
export const commentEventSchema = z.object({
  commentId: z.uuid(),
  activityId: z.uuid(),
  userId: z.uuid(),
});
export type CommentEvent = z.infer<typeof commentEventSchema>;

/**
 * Kudos given or removed (ADR-034 §4). Emitted only when the state really
 * changed: a repeated `PUT` or `DELETE` emits nothing.
 */
export const KUDOS_GIVEN_EVENT = "engagement.kudos.given";
export const KUDOS_REMOVED_EVENT = "engagement.kudos.removed";

/** `userId` is the athlete who gave or removed the kudos. */
export const kudosEventSchema = z.object({
  activityId: z.uuid(),
  userId: z.uuid(),
});
export type KudosEvent = z.infer<typeof kudosEventSchema>;
