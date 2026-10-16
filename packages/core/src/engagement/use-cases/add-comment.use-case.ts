import { ConflictException, Injectable } from "@nestjs/common";
import type { ActivityRecord } from "../../activities/index.js";
import type { CommentRecord } from "../domain/comment-record.js";
import { toCommentView, type CommentView } from "../domain/comment-view.js";
import { CommentRepository } from "../repositories/comment.repository.js";
import { CommentEvents } from "../services/comment-events.service.js";
import { CommentableActivity } from "../services/commentable-activity.service.js";

export interface AddCommentResult {
  comment: CommentView;
  /** `true` -> `201`; `false` -> `200`, a replay that wrote nothing. */
  created: boolean;
}

/**
 * `POST /v1/activities/:id/comments` (ADR-034 §2-4): idempotent on the
 * app-generated id. The same id by the same author on the same Activity
 * returns the stored comment and emits nothing; an id used by someone else,
 * on another Activity or by a deleted comment is a `409 comment_id_conflict`.
 * `engagement.comment.added` follows the commit.
 */
@Injectable()
export class AddCommentUseCase {
  constructor(
    private readonly access: CommentableActivity,
    private readonly comments: CommentRepository,
    private readonly events: CommentEvents,
  ) {}

  async execute(userId: string, activityId: string, request: { id: string; body: string }): Promise<AddCommentResult> {
    const activity = await this.access.get(userId, activityId);
    const existing = await this.comments.findById(request.id);
    if (existing) {
      return this.replay(userId, activity, existing);
    }
    const inserted = await this.comments.insertIfAbsent({
      id: request.id,
      activityId,
      userId,
      body: request.body,
      createdAt: new Date(),
    });
    const comment = await this.comments.findById(request.id);
    if (!inserted) {
      // Lost a race with a concurrent call carrying the same id.
      return this.replay(userId, activity, comment!);
    }
    this.events.added({ commentId: request.id, activityId, userId });
    return { comment: toCommentView(comment!, userId, activity.userId), created: true };
  }

  private replay(userId: string, activity: ActivityRecord, existing: CommentRecord): AddCommentResult {
    if (existing.userId !== userId || existing.activityId !== activity.id || existing.deletedAt) {
      throw new ConflictException({ code: "comment_id_conflict", message: "This comment id is already used" });
    }
    return { comment: toCommentView(existing, userId, activity.userId), created: false };
  }
}
