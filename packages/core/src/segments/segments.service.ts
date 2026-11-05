import { Injectable, NotFoundException } from "@nestjs/common";
import { SegmentFavoriteRepository } from "./repositories/segment-favorite.repository.js";
import type { MatchSegmentHistoryJob, MatchSegmentsJob, ReplaySegmentMedalsJob } from "@repo/contracts";
import { MatchSegmentsUseCase } from "./use-cases/match-segments.use-case.js";
import { MatchSegmentHistoryUseCase } from "./use-cases/match-segment-history.use-case.js";
import { ActivityEffortRepository } from "./repositories/activity-effort.repository.js";
import { ActivityMatchingRepository } from "./repositories/activity-matching.repository.js";
import { EffortRecorder } from "./services/effort-recorder.js";
import type { ActivityEffortRecord } from "./domain/activity-effort.js";
import { SEGMENT_MATCHING_VERSION } from "./domain/match-segment.js";
import { SEGMENT_SPORTS } from "./domain/segment-sports.js";
import type { ViewerExclusions } from "../infrastructure/index.js";
import {
  SegmentMapRepository,
  type MapSegmentRecord,
  type MapSegmentSearch,
} from "./repositories/segment-map.repository.js";

function segmentNotFound(): NotFoundException {
  return new NotFoundException({ code: "segment_not_found", message: "Segment not found" });
}

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
    private readonly mapSegments: SegmentMapRepository,
    private readonly favorites: SegmentFavoriteRepository,
  ) {}

  /** Stars a Segment (ADR-039 §5), idempotent; `404 segment_not_found`. */
  async favorite(userId: string, segmentId: string): Promise<void> {
    if (!(await this.favorites.add(userId, segmentId))) {
      throw segmentNotFound();
    }
  }

  /** Unstars a Segment, idempotent; `404 segment_not_found`. */
  async unfavorite(userId: string, segmentId: string): Promise<void> {
    if (!(await this.favorites.remove(userId, segmentId))) {
      throw segmentNotFound();
    }
  }

  /**
   * The Segments of a zone of the Map tab (ADR-039 §12), the most athletes first. `apps/api`
   * passes the viewer filter: it only hides blocked and banned athletes from `leaderTimeS`, never
   * from the counters (§8).
   */
  findOnMap(search: MapSegmentSearch, exclusions: ViewerExclusions): Promise<MapSegmentRecord[]> {
    return this.mapSegments.search(search, exclusions);
  }

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
}
