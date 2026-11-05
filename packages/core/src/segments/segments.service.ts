import { Injectable, NotFoundException } from "@nestjs/common";
import {
  OPEN_DATA_SEGMENTS_KEY,
  type MatchSegmentHistoryJob,
  type MatchSegmentsJob,
  type ReplaySegmentMedalsJob,
} from "@repo/contracts";
import { SegmentFavoriteRepository } from "./repositories/segment-favorite.repository.js";
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
import {
  ImportNervoSegmentsUseCase,
  type NervoImportReport,
} from "./use-cases/import-nervo-segments.use-case.js";
import { DeleteSegmentAsAdministratorUseCase } from "./use-cases/delete-segment-as-administrator.use-case.js";
import { ExportOpenSegmentsUseCase } from "./use-cases/export-open-segments.use-case.js";
import { StorageService, type PresignedUrl } from "../storage/index.js";
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
    private readonly importNervoSegmentsUseCase: ImportNervoSegmentsUseCase,
    private readonly deleteSegmentAsAdministratorUseCase: DeleteSegmentAsAdministratorUseCase,
    private readonly exportOpenSegmentsUseCase: ExportOpenSegmentsUseCase,
    private readonly storage: StorageService,
    private readonly effortResults: EffortResultsRepository,
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

  /**
   * `pnpm segments:import` (ADR-039 §10): the generator's NDJSON lines, idempotent on
   * `source_key`, then the per-Activity replay of `match-segments` at low priority (§7).
   */
  importNervoSegments(lines: AsyncIterable<string> | Iterable<string>): Promise<NervoImportReport> {
    return this.importNervoSegmentsUseCase.execute(lines);
  }

  /**
   * Deletes a Segment for good on an Administrator's decision (ADR-039 §10, §11; screen in #219);
   * a Nervo Segment's source key is excluded from every later import.
   */
  deleteSegmentAsAdministrator(segmentId: string): Promise<{ deleted: boolean; excludedSourceKey: string | null }> {
    return this.deleteSegmentAsAdministratorUseCase.execute(segmentId);
  }

  /** `export-segments-odbl` (ADR-039 §10, §13): rewrites the public ODbL file of every Segment. */
  exportOpenData(): Promise<{ segmentCount: number }> {
    return this.exportOpenSegmentsUseCase.execute();
  }

  /**
   * A pre-signed URL of the ODbL file for `GET /v1/open-data/segments.ndjson.gz` (ADR-039 §12),
   * `null` before the first export.
   */
  async openDataUrl(expiresInSeconds: number): Promise<PresignedUrl | null> {
    if (!(await this.storage.headObject(OPEN_DATA_SEGMENTS_KEY))) {
      return null;
    }
    return this.storage.presignGet(OPEN_DATA_SEGMENTS_KEY, expiresInSeconds);
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
