import { Injectable, UnprocessableEntityException } from "@nestjs/common";
import {
  decodeCommentCursor,
  encodeCommentCursor,
  InvalidCommentCursorError,
  type CommentCursor,
} from "../domain/comment-cursor.js";
import { toCommentView, type CommentPage } from "../domain/comment-view.js";
import { CommentRepository } from "../repositories/comment.repository.js";
import { CommentableActivity } from "../services/commentable-activity.service.js";

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
    const before = query.before === undefined ? undefined : this.decode(query.before);
    const rows = await this.comments.findPage(activityId, before, query.limit + 1);
    const page = rows.slice(0, query.limit);
    const oldest = page.at(-1);
    return {
      items: page.reverse().map((row) => toCommentView(row, viewerId, activity.userId)),
      previousCursor:
        rows.length > query.limit && oldest ? encodeCommentCursor({ createdAt: oldest.createdAt, id: oldest.id }) : null,
    };
  }

  private decode(cursor: string): CommentCursor {
    try {
      return decodeCommentCursor(cursor);
    } catch (error) {
      if (error instanceof InvalidCommentCursorError) {
        throw new UnprocessableEntityException({ code: "invalid_cursor", message: "Invalid comment cursor" });
      }
      throw error;
    }
  }
}
