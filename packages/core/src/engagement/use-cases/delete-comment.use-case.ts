import { ForbiddenException, Injectable } from "@nestjs/common";
import { CommentRepository } from "../repositories/comment.repository.js";
import { CommentEvents } from "../services/comment-events.service.js";
import { CommentableActivity } from "../services/commentable-activity.service.js";
import { commentNotFound } from "../services/comment-not-found.js";

/**
 * `DELETE /v1/activities/:id/comments/:commentId` (ADR-034 §2-4): the
 * comment's author or the Activity's author (`403` otherwise). Soft
 * delete (ADR-017), idempotent: an already deleted comment resolves
 * without writing or emitting. `engagement.comment.deleted` follows the
 * commit, with the deleter as `userId`.
 */
@Injectable()
export class DeleteCommentUseCase {
  constructor(
    private readonly access: CommentableActivity,
    private readonly comments: CommentRepository,
    private readonly events: CommentEvents,
  ) {}

  async execute(userId: string, activityId: string, commentId: string): Promise<void> {
    const activity = await this.access.get(userId, activityId);
    const comment = await this.comments.findById(commentId);
    if (!comment || comment.activityId !== activityId) {
      throw commentNotFound();
    }
    if (comment.userId !== userId && activity.userId !== userId) {
      throw new ForbiddenException({
        code: "not_allowed_to_delete_comment",
        message: "Only the comment's author or the activity's author can delete it",
      });
    }
    if (await this.comments.softDelete(commentId, new Date())) {
      this.events.deleted({ commentId, activityId, userId });
    }
  }
}
