import { Injectable } from "@nestjs/common";
import { ActivitiesService } from "../../activities/index.js";
import { isAthleteHidden, type ViewerExclusions } from "../../infrastructure/index.js";
import type { CommentRecord } from "../domain/comment-record.js";
import { toCommentView, type CommentView } from "../domain/comment-view.js";
import { CommentRepository } from "../repositories/comment.repository.js";
import { CommentableActivity } from "../services/commentable-activity.service.js";
import { commentNotFound } from "../services/comment-not-found.js";

/**
 * `GET /v1/activities/:id/comments/:commentId` (ADR-034 §3), used by the
 * app's realtime handling: `404 comment_not_found` when the comment is
 * unknown, deleted, on another Activity, or hidden by the viewer filter
 * (ADR-038 §7).
 */
@Injectable()
export class GetCommentUseCase {
  constructor(
    private readonly access: CommentableActivity,
    private readonly comments: CommentRepository,
    private readonly activities: ActivitiesService,
  ) {}

  async execute(
    viewerId: string,
    activityId: string,
    commentId: string,
    exclusions: ViewerExclusions,
  ): Promise<CommentView> {
    const activity = await this.access.get(viewerId, activityId, exclusions);
    const comment = await this.comments.findById(commentId);
    if (!comment || comment.activityId !== activityId || !isShown(comment, exclusions)) {
      throw commentNotFound();
    }
    return toCommentView(comment, viewerId, activity.userId);
  }

  /**
   * A live comment the viewer may see, under an Activity they may see, whatever its Activity:
   * what a Report of a comment needs (ADR-038 §9). `null` otherwise.
   */
  async findVisible(viewerId: string, commentId: string, exclusions: ViewerExclusions): Promise<CommentRecord | null> {
    const comment = await this.comments.findById(commentId);
    if (!comment || !isShown(comment, exclusions)) {
      return null;
    }
    const activity = await this.activities.getVisible(viewerId, comment.activityId, exclusions);
    return activity ? comment : null;
  }
}

function isShown(comment: CommentRecord, exclusions: ViewerExclusions): boolean {
  return (
    comment.deletedAt === null &&
    !isAthleteHidden(exclusions, comment.userId) &&
    !exclusions.reportedCommentIds.includes(comment.id)
  );
}
