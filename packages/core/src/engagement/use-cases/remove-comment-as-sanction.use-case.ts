import { Injectable } from "@nestjs/common";
import type { CommentRecord } from "../domain/comment-record.js";
import { CommentRepository } from "../repositories/comment.repository.js";
import { CommentEvents } from "../services/comment-events.service.js";
import { commentNotFound } from "../services/comment-not-found.js";

/**
 * « Retirer un commentaire » (`DELETE /v1/admin/comments/:id`, ADR-038 §11), a Sanction: the
 * soft delete of ADR-034 without the author check. `404 comment_not_found` for a comment unknown
 * or already deleted, so nothing is recorded nor sent twice. `engagement.comment.deleted`
 * follows the commit with the Administrator as `userId` and `bySanction: true`. Returns the
 * comment as it was, for the e-mail to its author.
 */
@Injectable()
export class RemoveCommentAsSanctionUseCase {
  constructor(
    private readonly comments: CommentRepository,
    private readonly events: CommentEvents,
  ) {}

  async execute(administratorId: string, commentId: string): Promise<CommentRecord> {
    const comment = await this.comments.findById(commentId);
    if (!comment || comment.deletedAt !== null || !(await this.comments.softDelete(comment.id, new Date()))) {
      throw commentNotFound();
    }
    this.events.deleted({
      commentId: comment.id,
      activityId: comment.activityId,
      userId: administratorId,
      authorId: comment.userId,
      bySanction: true,
    });
    return comment;
  }
}
