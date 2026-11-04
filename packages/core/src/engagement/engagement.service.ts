import { Injectable } from "@nestjs/common";
import type { InstantRange, PageQuery, ViewerExclusions } from "../infrastructure/index.js";
import {
  EngagementAdminStatsRepository,
  type EngagementGrowthCounts,
} from "./repositories/engagement-admin-stats.repository.js";
import { GiveKudosUseCase } from "./use-cases/give-kudos.use-case.js";
import { AddCommentUseCase, type AddCommentResult } from "./use-cases/add-comment.use-case.js";
import { ListCommentsUseCase } from "./use-cases/list-comments.use-case.js";
import { GetCommentUseCase } from "./use-cases/get-comment.use-case.js";
import { EditCommentUseCase } from "./use-cases/edit-comment.use-case.js";
import { DeleteCommentUseCase } from "./use-cases/delete-comment.use-case.js";
import { ListKudosUseCase } from "./use-cases/list-kudos.use-case.js";
import { GetEngagementCountsUseCase } from "./use-cases/get-engagement-counts.use-case.js";
import { KudosRepository } from "./repositories/kudos.repository.js";
import { CommentRepository } from "./repositories/comment.repository.js";
import { RemoveCommentAsSanctionUseCase } from "./use-cases/remove-comment-as-sanction.use-case.js";
import type { CommentRecord } from "./domain/comment-record.js";
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
    private readonly adminStats: EngagementAdminStatsRepository,
    private readonly giveKudosUseCase: GiveKudosUseCase,
    private readonly listKudosUseCase: ListKudosUseCase,
    private readonly addCommentUseCase: AddCommentUseCase,
    private readonly listCommentsUseCase: ListCommentsUseCase,
    private readonly getCommentUseCase: GetCommentUseCase,
    private readonly editCommentUseCase: EditCommentUseCase,
    private readonly deleteCommentUseCase: DeleteCommentUseCase,
    private readonly getEngagementCountsUseCase: GetEngagementCountsUseCase,
    private readonly kudos: KudosRepository,
    private readonly comments: CommentRepository,
    private readonly removeCommentAsSanctionUseCase: RemoveCommentAsSanctionUseCase,
  ) {}

  /** Backoffice dashboard, "Croissance" (ADR-038 §15): kudos and comments given in `range`. */
  getAdminGrowthCounts(range: InstantRange, excludedUserIds: readonly string[]): Promise<EngagementGrowthCounts> {
    return this.adminStats.countGrowth(range, excludedUserIds);
  }

  // Reads and new engagement on a viewer's behalf take the viewer filter (ADR-038 §7): hidden
  // athletes' comments and kudos, and comments the viewer reported, are left out; counts are not.

  giveKudos(userId: string, activityId: string, exclusions: ViewerExclusions): Promise<KudosState> {
    return this.giveKudosUseCase.execute(userId, activityId, exclusions);
  }

  removeKudos(userId: string, activityId: string, exclusions: ViewerExclusions): Promise<KudosState> {
    return this.giveKudosUseCase.remove(userId, activityId, exclusions);
  }

  /** `GET /v1/activities/:id/kudos` (ADR-034 §1): most recent first, keyset pages. */
  listKudos(viewerId: string, activityId: string, query: PageQuery, exclusions: ViewerExclusions): Promise<KudosPage> {
    return this.listKudosUseCase.execute(viewerId, activityId, query, exclusions);
  }

  /** Batch read (ADR-029): which of `activityIds` the viewer gave kudos to. */
  getKudoedBy(userId: string, activityIds: string[]): Promise<Set<string>> {
    return this.kudos.findKudoedActivityIds(userId, activityIds);
  }

  /**
   * Batch read (ADR-036 §5): the user ids of the last `perActivity` kudos givers of each
   * activity, most recent first, hidden athletes left out. Activities without kudos are absent.
   */
  getRecentKudoers(
    activityIds: string[],
    perActivity: number,
    exclusions: ViewerExclusions,
  ): Promise<Map<string, string[]>> {
    return this.kudos.findRecentGiverIds(activityIds, perActivity, exclusions.hiddenAthleteIds);
  }

  /** `GET /v1/activities/:id/comments` (ADR-034 §3). */
  listComments(
    viewerId: string,
    activityId: string,
    query: { before?: string; limit: number },
    exclusions: ViewerExclusions,
  ): Promise<CommentPage> {
    return this.listCommentsUseCase.execute(viewerId, activityId, query, exclusions);
  }

  /** `GET /v1/activities/:id/comments/:commentId` (ADR-034 §3). */
  getComment(
    viewerId: string,
    activityId: string,
    commentId: string,
    exclusions: ViewerExclusions,
  ): Promise<CommentView> {
    return this.getCommentUseCase.execute(viewerId, activityId, commentId, exclusions);
  }

  /**
   * A live comment the viewer may see, whatever its Activity, with its author and text: the
   * target of a Report (ADR-038 §9). `null` when unknown, deleted or not visible.
   */
  findVisibleComment(
    viewerId: string,
    commentId: string,
    exclusions: ViewerExclusions,
  ): Promise<{ id: string; activityId: string; authorId: string; body: string } | null> {
    return this.getCommentUseCase
      .findVisible(viewerId, commentId, exclusions)
      .then((comment) =>
        comment ? { id: comment.id, activityId: comment.activityId, authorId: comment.userId, body: comment.body } : null,
      );
  }

  /** `POST /v1/activities/:id/comments` (ADR-034 §3), idempotent on the app-generated id. */
  addComment(
    userId: string,
    activityId: string,
    request: { id: string; body: string },
    exclusions: ViewerExclusions,
  ): Promise<AddCommentResult> {
    return this.addCommentUseCase.execute(userId, activityId, request, exclusions);
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

  // --- Backoffice (ADR-038 §11) ---

  /** An Activity's comments not deleted, newest first, at most `limit`, whatever its visibility. */
  listCommentsForAdmin(activityId: string, limit: number): Promise<CommentRecord[]> {
    return this.comments.findPage(activityId, undefined, limit);
  }

  /** An Activity's kudos, most recent first, at most `limit`, whatever its visibility. */
  async listKudosForAdmin(activityId: string, limit: number): Promise<{ userId: string; createdAt: Date }[]> {
    const rows = await this.kudos.findPage(activityId, undefined, limit);
    return rows.map(({ userId, createdAt }) => ({ userId, createdAt }));
  }

  /**
   * Sanction: soft deletes a comment without the author check; `404 comment_not_found` when it
   * is unknown or already deleted. Returns the comment as it was.
   */
  removeCommentAsSanction(administratorId: string, commentId: string): Promise<CommentRecord> {
    return this.removeCommentAsSanctionUseCase.execute(administratorId, commentId);
  }

  /** Batch read: the ids among `commentIds` of comments not deleted (Journal links). */
  getExistingCommentIds(commentIds: string[]): Promise<Set<string>> {
    return this.comments.findExistingIds(commentIds);
  }
}
