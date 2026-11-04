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
 * `engagement.comment.deleted`: `userId` is the deleter (the comment's author, the Activity's
 * author, or the Administrator); `bySanction` is true when an Administrator removed it as a
 * Sanction (ADR-038 §4, §10), and `authorId` is the comment's author in every case.
 */
export const commentDeletedEventSchema = commentEventSchema.extend({
  authorId: z.uuid(),
  bySanction: z.boolean(),
});
export type CommentDeletedEvent = z.infer<typeof commentDeletedEventSchema>;

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
