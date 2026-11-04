import { Injectable } from "@nestjs/common";
import { readKeysetPage, type ViewerExclusions } from "../../infrastructure/index.js";
import { decodeCommentCursor, encodeCommentCursor } from "../domain/comment-cursor.js";
import { toCommentView, type CommentPage } from "../domain/comment-view.js";
import { CommentRepository } from "../repositories/comment.repository.js";
import { CommentableActivity } from "../services/commentable-activity.service.js";

/**
 * `GET /v1/activities/:id/comments` (ADR-034 §3): the newest page of
 * non-deleted comments, or the page older than `before`, returned in
 * chronological order with the cursor to the next older page. Comments of
 * hidden athletes and those the viewer reported are left out (ADR-038 §7);
 * the comment count is not changed.
 */
@Injectable()
export class ListCommentsUseCase {
  constructor(
    private readonly access: CommentableActivity,
    private readonly comments: CommentRepository,
  ) {}

  async execute(
    viewerId: string,
    activityId: string,
    query: { before?: string; limit: number },
    exclusions: ViewerExclusions,
  ): Promise<CommentPage> {
    const activity = await this.access.get(viewerId, activityId, exclusions);
    const { rows, boundary: oldest } = await readKeysetPage(
      { cursor: query.before, limit: query.limit },
      decodeCommentCursor,
      (before, take) => this.comments.findPage(activityId, before, take, exclusions),
    );
    return {
      items: rows.reverse().map((row) => toCommentView(row, viewerId, activity.userId)),
      previousCursor: oldest ? encodeCommentCursor({ createdAt: oldest.createdAt, id: oldest.id }) : null,
    };
  }
}
