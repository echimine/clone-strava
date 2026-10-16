import type { CommentRecord } from "./comment-record.js";

/**
 * A non-deleted comment as seen by a viewer (ADR-034 §3). The author is an
 * id only: `apps/api` assembles identities (ADR-029 §2).
 */
export interface CommentView {
  id: string;
  activityId: string;
  authorId: string;
  body: string;
  createdAt: Date;
  updatedAt: Date | null;
  /** The viewer wrote the comment. */
  viewerCanEdit: boolean;
  /** The viewer wrote the comment or the Activity. */
  viewerCanDelete: boolean;
}

/** A page of comments in chronological order; `previousCursor` is null when none is older. */
export interface CommentPage {
  items: CommentView[];
  previousCursor: string | null;
}

export function toCommentView(comment: CommentRecord, viewerId: string, activityAuthorId: string): CommentView {
  return {
    id: comment.id,
    activityId: comment.activityId,
    authorId: comment.userId,
    body: comment.body,
    createdAt: comment.createdAt,
    updatedAt: comment.updatedAt,
    viewerCanEdit: comment.userId === viewerId,
    viewerCanDelete: comment.userId === viewerId || activityAuthorId === viewerId,
  };
}
