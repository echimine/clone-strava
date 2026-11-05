import { Injectable } from "@nestjs/common";
import type { MatchSegmentHistoryJob, MatchSegmentsJob, ReplaySegmentMedalsJob } from "@repo/contracts";
import { MatchSegmentsUseCase } from "./use-cases/match-segments.use-case.js";
import { MatchSegmentHistoryUseCase } from "./use-cases/match-segment-history.use-case.js";
import { ActivityEffortRepository } from "./repositories/activity-effort.repository.js";
import { ActivityMatchingRepository } from "./repositories/activity-matching.repository.js";
import { EffortRecorder } from "./services/effort-recorder.js";
import type { ActivityEffortRecord } from "./domain/activity-effort.js";
import { SEGMENT_MATCHING_VERSION } from "./domain/match-segment.js";
import { SEGMENT_SPORTS } from "./domain/segment-sports.js";
import {
  GetSegmentLeaderboardUseCase,
  type LeaderboardReader,
  type LeaderboardRequest,
  type LeaderboardView,
} from "./use-cases/get-segment-leaderboard.use-case.js";
import { GetSegmentSheetUseCase, type SegmentSheetView } from "./use-cases/get-segment-sheet.use-case.js";
import { SegmentSheetRepository } from "./repositories/segment-sheet.repository.js";
import { LeaderboardRepository } from "./repositories/leaderboard.repository.js";
import type { ViewerExclusions } from "../infrastructure/index.js";

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
    private readonly getLeaderboardUseCase: GetSegmentLeaderboardUseCase,
    private readonly getSheetUseCase: GetSegmentSheetUseCase,
    private readonly sheets: SegmentSheetRepository,
    private readonly leaderboards: LeaderboardRepository,
  ) {}

  /**
   * The current Local Legend (Tous) of each Segment that has one, after the viewer filter
   * (ADR-039 §8): the laurel crown on an Effort whose athlete holds the title. Nothing stored.
   */
  async getLocalLegends(segmentIds: readonly string[], exclusions: ViewerExclusions): Promise<Map<string, string>> {
    const legends = await this.leaderboards.findLocalLegends(segmentIds, "all", exclusions.hiddenAthleteIds);
    return new Map([...legends].map(([segmentId, legend]) => [segmentId, legend.userId]));
  }

  /** A Report's target (ADR-039 §11): `undefined` once deleted. The creator is never shown. */
  getReportTarget(segmentId: string): Promise<{ name: string; createdBy: string | null } | undefined> {
    return this.sheets.findReportTarget(segmentId);
  }

  /** `GET /v1/segments/:id` (ADR-039 §12): free; `404 segment_not_found` once deleted. */
  getSheet(segmentId: string, reader: LeaderboardReader): Promise<SegmentSheetView> {
    return this.getSheetUseCase.execute(segmentId, reader);
  }

  /**
   * `GET /v1/segments/:id/leaderboard` (ADR-039 §8, §9): `404 segment_not_found`,
   * `403 premium_required`, `422` for an unknown filter or cursor.
   */
  getLeaderboard(segmentId: string, request: LeaderboardRequest, reader: LeaderboardReader): Promise<LeaderboardView> {
    return this.getLeaderboardUseCase.execute(segmentId, request, reader);
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
