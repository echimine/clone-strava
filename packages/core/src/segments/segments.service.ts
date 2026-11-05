import { Injectable } from "@nestjs/common";
import type {
  ListSegmentFavoritesQuery,
  ListSegmentFavoritesResponse,
  MatchSegmentHistoryJob,
  MatchSegmentsJob,
  ReplaySegmentMedalsJob,
} from "@repo/contracts";
import { MatchSegmentsUseCase } from "./use-cases/match-segments.use-case.js";
import { MatchSegmentHistoryUseCase } from "./use-cases/match-segment-history.use-case.js";
import { ActivityEffortRepository } from "./repositories/activity-effort.repository.js";
import { ActivityMatchingRepository } from "./repositories/activity-matching.repository.js";
import { EffortRecorder } from "./services/effort-recorder.js";
import type { ActivityEffortRecord } from "./domain/activity-effort.js";
import { SEGMENT_MATCHING_VERSION } from "./domain/match-segment.js";
import { SEGMENT_SPORTS } from "./domain/segment-sports.js";
import { SegmentCreationRepository } from "./repositories/segment-creation.repository.js";
import { ManageOwnSegmentUseCase } from "./use-cases/manage-own-segment.use-case.js";
import { SegmentFavoritesUseCase } from "./use-cases/segment-favorites.use-case.js";

/** ADR-039 §13: Activities the sweep enqueues at most per run. */
export const RECONCILE_SEGMENT_MATCHING_BATCH = 100;

/**
 * Public facade of the `segments` module (ADR-021 §1: layer 3, may depend on `activities`,
 * `sports`, `users`).
 */
@Injectable()
export class SegmentsService {
  constructor(
    private readonly matchSegmentsUseCase: MatchSegmentsUseCase,
    private readonly matchSegmentHistoryUseCase: MatchSegmentHistoryUseCase,
    private readonly activityEfforts: ActivityEffortRepository,
    private readonly matchings: ActivityMatchingRepository,
    private readonly recorder: EffortRecorder,
    private readonly ownSegments: ManageOwnSegmentUseCase,
    private readonly favorites: SegmentFavoritesUseCase,
    private readonly creations: SegmentCreationRepository,
  ) {}

  /** Called by `apps/worker`'s `match-segments` processor (ADR-011 §1, ADR-039 §6). */
  matchSegments(job: MatchSegmentsJob): Promise<void> {
    return this.matchSegmentsUseCase.execute(job);
  }

  /**
   * One page of a new Segment's retro-matching (ADR-039 §7); the worker enqueues the next page
   * with the returned cursor, `null` once done or when the Segment is gone.
   */
  matchSegmentHistory(job: MatchSegmentHistoryJob): Promise<{ nextCursor: string } | null> {
    return this.matchSegmentHistoryUseCase.execute(job);
  }

  /**
   * Replays every Segment Medal of the athlete (ADR-039 §8): after an Activity is deleted, and
   * whenever an Effort is rejected or reinstated.
   */
  replayMedals(job: ReplaySegmentMedalsJob): Promise<void> {
    return this.recorder.replayAll(job.userId);
  }

  /**
   * `reconcile-segment-matching` (ADR-039 §13): processed Activities of the sports with a map
   * never matched or matched with an older version, for the worker to enqueue.
   */
  findActivitiesToMatch(): Promise<Array<{ activityId: string; userId: string }>> {
    return this.matchings.findLagging(SEGMENT_SPORTS, SEGMENT_MATCHING_VERSION, RECONCILE_SEGMENT_MATCHING_BATCH);
  }

  /** An Activity's efforts on Segments, read-only in the backoffice (ADR-038 §11). */
  getActivityEfforts(activityId: string): Promise<ActivityEffortRecord[]> {
    return this.activityEfforts.findByActivityId(activityId);
  }

  /** `PATCH /v1/segments/:id` (ADR-039 §5): the creator only, no recomputation. */
  rename(userId: string, segmentId: string, name: string): Promise<{ id: string; name: string }> {
    return this.ownSegments.rename(userId, segmentId, name);
  }

  /** `DELETE /v1/segments/:id` (ADR-039 §5, §11): the creator only, `409 has_other_efforts`. */
  deleteOwn(userId: string, segmentId: string): Promise<void> {
    return this.ownSegments.delete(userId, segmentId);
  }

  /** `PUT /v1/segments/:id/favorite`: idempotent, `404` for an unknown Segment. */
  favorite(userId: string, segmentId: string): Promise<void> {
    return this.favorites.favorite(userId, segmentId);
  }

  /** `DELETE /v1/segments/:id/favorite`: idempotent, `404` for an unknown Segment. */
  unfavorite(userId: string, segmentId: string): Promise<void> {
    return this.favorites.unfavorite(userId, segmentId);
  }

  /** `GET /v1/me/segment-favorites`: Plus › « Segments ». */
  listFavorites(userId: string, query: ListSegmentFavoritesQuery): Promise<ListSegmentFavoritesResponse> {
    return this.favorites.list(userId, query);
  }

  /**
   * Account deletion (ADR-039 §11, amends ADR-038 §13), just before the cascade: deletes the
   * Segments the athlete created that nobody else has an Effort on (a running retro-matching does
   * not count); the others stay, with `created_by` set to null by the foreign key.
   */
  deleteSegmentsOnlyTheirs(userId: string): Promise<number> {
    return this.creations.deleteOnlyTheirs(userId);
  }
}
