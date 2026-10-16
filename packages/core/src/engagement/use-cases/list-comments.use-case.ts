import { Injectable } from "@nestjs/common";
import { decodeCommentCursor, encodeCommentCursor } from "../domain/comment-cursor.js";
import { toCommentView, type CommentPage } from "../domain/comment-view.js";
import { CommentRepository } from "../repositories/comment.repository.js";
import { CommentableActivity } from "../services/commentable-activity.service.js";
import { readKeysetPage } from "../services/keyset-page.js";

/**
 * `GET /v1/activities/:id/comments` (ADR-034 §3): the newest page of
 * non-deleted comments, or the page older than `before`, returned in
 * chronological order with the cursor to the next older page.
 */
@Injectable()
export class ListCommentsUseCase {
  constructor(
    private readonly access: CommentableActivity,
    private readonly comments: CommentRepository,
  ) {}

  async execute(viewerId: string, activityId: string, query: { before?: string; limit: number }): Promise<CommentPage> {
    const activity = await this.access.get(viewerId, activityId);
    const { rows, boundary: oldest } = await readKeysetPage(
      { cursor: query.before, limit: query.limit },
      decodeCommentCursor,
      (before, take) => this.comments.findPage(activityId, before, take),
    );
    return {
      items: rows.reverse().map((row) => toCommentView(row, viewerId, activity.userId)),
      previousCursor: oldest ? encodeCommentCursor({ createdAt: oldest.createdAt, id: oldest.id }) : null,
    };
  }
}
