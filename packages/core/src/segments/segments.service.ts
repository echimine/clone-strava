import { Injectable } from "@nestjs/common";
import type { MatchSegmentHistoryJob, MatchSegmentsJob, ReplaySegmentMedalsJob } from "@repo/contracts";
import { MatchSegmentsUseCase } from "./use-cases/match-segments.use-case.js";
import { MatchSegmentHistoryUseCase } from "./use-cases/match-segment-history.use-case.js";
import { ActivityEffortRepository } from "./repositories/activity-effort.repository.js";
import { ActivityMatchingRepository } from "./repositories/activity-matching.repository.js";
import { EffortRecorder } from "./services/effort-recorder.js";
import type { ActivityEffortRecord } from "./domain/activity-effort.js";
import type { ActivitySegmentResults, EffortMedalCount } from "./domain/effort-result.js";
import { EffortResultsRepository } from "./repositories/effort-results.repository.js";
import { SEGMENT_MATCHING_VERSION } from "./domain/match-segment.js";
import { SEGMENT_SPORTS } from "./domain/segment-sports.js";

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
    private readonly effortResults: EffortResultsRepository,
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

  /**
   * « Résultats » of an Activity on the `segments` side (ADR-039 §12): whether its matching is
   * still in progress, and its Efforts the viewer may see, in trace order. The caller has checked
   * that the viewer may see the Activity.
   */
  async getActivityResults(activityId: string, viewerId: string): Promise<ActivitySegmentResults> {
    const [matchingInProgress, rows] = await Promise.all([
      this.effortResults.isMatchingInProgress(activityId, SEGMENT_MATCHING_VERSION),
      this.effortResults.findByActivity(activityId, viewerId),
    ]);
    const legends = await this.localLegendsAmong(rows);
    return {
      matchingInProgress,
      efforts: rows.map((row) => ({
        id: row.id,
        segment: { id: row.segmentId, name: row.segmentName, distanceM: row.segmentDistanceM, verified: row.verified },
        elapsedTimeS: row.elapsedTimeS,
        medal: row.medal,
        isFirstPass: row.isFirstPass,
        localLegend: legends.has(`${row.segmentId}:${row.userId}`),
        startPoint: { lat: row.startLat, lon: row.startLon },
      })),
    };
  }

  /**
   * The Medals of the Efforts of a page of Activities the viewer may see (« Performances »,
   * ADR-039 §12), per Activity and Medal. A deleted Segment takes its Efforts with it.
   */
  countEffortMedals(activityIds: string[], viewerId: string): Promise<EffortMedalCount[]> {
    return this.effortResults.countMedals(activityIds, viewerId);
  }

  /**
   * `segmentId:userId` pairs whose athlete currently holds the Segment's Local Legend (Tous,
   * ADR-039 §8). Extension point: the Local Legend is computed by the Segment sheet (#251); until
   * it is available here, nobody wears the crown in « Résultats ».
   */
  private async localLegendsAmong(_efforts: ReadonlyArray<{ segmentId: string; userId: string }>): Promise<Set<string>> {
    return new Set();
  }
}
