import { ForbiddenException, Injectable } from "@nestjs/common";
import { toCommentView, type CommentView } from "../domain/comment-view.js";
import { CommentRepository } from "../repositories/comment.repository.js";
import { CommentEvents } from "../services/comment-events.service.js";
import { CommentableActivity } from "../services/commentable-activity.service.js";
import { commentNotFound } from "../services/comment-not-found.js";

/**
 * `PATCH /v1/activities/:id/comments/:commentId` (ADR-034 §2-4): the
 * comment's author only (`403 not_comment_author`), no time limit; sets
 * `updated_at`. `engagement.comment.edited` follows the commit.
 */
@Injectable()
export class EditCommentUseCase {
  constructor(
    private readonly access: CommentableActivity,
    private readonly comments: CommentRepository,
    private readonly events: CommentEvents,
  ) {}

  async execute(userId: string, activityId: string, commentId: string, body: string): Promise<CommentView> {
    const activity = await this.access.get(userId, activityId);
    const comment = await this.comments.findById(commentId);
    if (!comment || comment.activityId !== activityId || comment.deletedAt) {
      throw commentNotFound();
    }
    if (comment.userId !== userId) {
      throw new ForbiddenException({ code: "not_comment_author", message: "Only the comment's author can edit it" });
    }
    const updated = await this.comments.updateBody(commentId, body, new Date());
    if (!updated) {
      // Deleted between the read and the write.
      throw commentNotFound();
    }
    this.events.edited({ commentId, activityId, userId });
    return toCommentView(updated, userId, activity.userId);
  }
}
