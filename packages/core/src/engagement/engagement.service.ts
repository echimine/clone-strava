import { Injectable } from "@nestjs/common";
import { GiveKudosUseCase } from "./use-cases/give-kudos.use-case.js";
import { AddCommentUseCase, type AddCommentResult } from "./use-cases/add-comment.use-case.js";
import { ListCommentsUseCase } from "./use-cases/list-comments.use-case.js";
import { GetCommentUseCase } from "./use-cases/get-comment.use-case.js";
import { EditCommentUseCase } from "./use-cases/edit-comment.use-case.js";
import { DeleteCommentUseCase } from "./use-cases/delete-comment.use-case.js";
import { ListKudosUseCase } from "./use-cases/list-kudos.use-case.js";
import { GetEngagementCountsUseCase } from "./use-cases/get-engagement-counts.use-case.js";
import { KudosRepository } from "./repositories/kudos.repository.js";
import type { CommentPage, CommentView } from "./domain/comment-view.js";
import type { EngagementCounts } from "./domain/engagement-counts.js";
import type { KudosState } from "./domain/kudos-state.js";
import type { KudosPage } from "./domain/kudos-view.js";

/**
 * Public facade of the `engagement` module (ADR-021 §1: layer 3, may
 * depend on `activities`, `social`, `users`).
 */
@Injectable()
export class EngagementService {
  constructor(
    private readonly giveKudosUseCase: GiveKudosUseCase,
    private readonly listKudosUseCase: ListKudosUseCase,
    private readonly addCommentUseCase: AddCommentUseCase,
    private readonly listCommentsUseCase: ListCommentsUseCase,
    private readonly getCommentUseCase: GetCommentUseCase,
    private readonly editCommentUseCase: EditCommentUseCase,
    private readonly deleteCommentUseCase: DeleteCommentUseCase,
    private readonly getEngagementCountsUseCase: GetEngagementCountsUseCase,
    private readonly kudos: KudosRepository,
  ) {}

  giveKudos(userId: string, activityId: string): Promise<KudosState> {
    return this.giveKudosUseCase.execute(userId, activityId);
  }

  removeKudos(userId: string, activityId: string): Promise<KudosState> {
    return this.giveKudosUseCase.remove(userId, activityId);
  }

  /** `GET /v1/activities/:id/kudos` (ADR-034 §1): most recent first, keyset pages. */
  listKudos(viewerId: string, activityId: string, query: { cursor?: string; limit: number }): Promise<KudosPage> {
    return this.listKudosUseCase.execute(viewerId, activityId, query);
  }

  /** Batch read (ADR-029): which of `activityIds` the viewer gave kudos to. */
  getKudoedBy(userId: string, activityIds: string[]): Promise<Set<string>> {
    return this.kudos.findKudoedActivityIds(userId, activityIds);
  }

  /** `GET /v1/activities/:id/comments` (ADR-034 §3). */
  listComments(viewerId: string, activityId: string, query: { before?: string; limit: number }): Promise<CommentPage> {
    return this.listCommentsUseCase.execute(viewerId, activityId, query);
  }

  /** `GET /v1/activities/:id/comments/:commentId` (ADR-034 §3). */
  getComment(viewerId: string, activityId: string, commentId: string): Promise<CommentView> {
    return this.getCommentUseCase.execute(viewerId, activityId, commentId);
  }

  /** `POST /v1/activities/:id/comments` (ADR-034 §3), idempotent on the app-generated id. */
  addComment(userId: string, activityId: string, request: { id: string; body: string }): Promise<AddCommentResult> {
    return this.addCommentUseCase.execute(userId, activityId, request);
  }

  /** `PATCH /v1/activities/:id/comments/:commentId` (ADR-034 §3): the comment's author only. */
  editComment(userId: string, activityId: string, commentId: string, body: string): Promise<CommentView> {
    return this.editCommentUseCase.execute(userId, activityId, commentId, body);
  }

  /** `DELETE /v1/activities/:id/comments/:commentId` (ADR-034 §3): soft delete, idempotent. */
  deleteComment(userId: string, activityId: string, commentId: string): Promise<void> {
    return this.deleteCommentUseCase.execute(userId, activityId, commentId);
  }

  /** Batch read (ADR-021 §2 rule 6): used by list screens (feed step 4). */
  getCounts(activityIds: string[]): Promise<Map<string, EngagementCounts>> {
    return this.getEngagementCountsUseCase.execute(activityIds);
  }
}
