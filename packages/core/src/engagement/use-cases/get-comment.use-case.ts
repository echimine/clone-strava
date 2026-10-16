import { Injectable } from "@nestjs/common";
import { toCommentView, type CommentView } from "../domain/comment-view.js";
import { CommentRepository } from "../repositories/comment.repository.js";
import { CommentableActivity } from "../services/commentable-activity.service.js";
import { commentNotFound } from "./comment-not-found.js";

/**
 * `GET /v1/activities/:id/comments/:commentId` (ADR-034 §3), used by the
 * app's realtime handling: `404 comment_not_found` when the comment is
 * unknown, deleted or on another Activity.
 */
@Injectable()
export class GetCommentUseCase {
  constructor(
    private readonly access: CommentableActivity,
    private readonly comments: CommentRepository,
  ) {}

  async execute(viewerId: string, activityId: string, commentId: string): Promise<CommentView> {
    const activity = await this.access.get(viewerId, activityId);
    const comment = await this.comments.findById(commentId);
    if (!comment || comment.activityId !== activityId || comment.deletedAt) {
      throw commentNotFound();
    }
    return toCommentView(comment, viewerId, activity.userId);
  }
}
