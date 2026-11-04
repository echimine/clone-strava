import { Injectable } from "@nestjs/common";
import { NO_EXCLUSIONS, type ViewerExclusions } from "../../infrastructure/index.js";
import { activityProcessingErrorCodeSchema, type ActivityProcessingErrorCode } from "@repo/contracts";
import { ActivityStatsRepository } from "../repositories/activity-stats.repository.js";
import { ActivityTrackRepository } from "../repositories/activity-track.repository.js";
import { ActivityAnalysisRepository } from "../repositories/activity-analysis.repository.js";
import { ActivityImportRepository } from "../repositories/activity-import.repository.js";
import type { ActivityDetailRecord } from "../domain/activity-detail.js";
import { activityNotFound } from "../services/activity-not-found.js";
import { GetVisibleActivityUseCase } from "./get-visible-activity.use-case.js";

/**
 * `GET /v1/activities/:id` (ADR-033 §2, amends ADR-031 §13): the Activity
 * with its official values and track fields, for any viewer who may see it.
 * The author gets it in any state (the app's resync relies on it, ADR-008
 * §6); others only once processed. `404 activity_not_found` otherwise,
 * without revealing that the id exists.
 */
@Injectable()
export class GetActivityDetailUseCase {
  constructor(
    private readonly visible: GetVisibleActivityUseCase,
    private readonly activityStats: ActivityStatsRepository,
    private readonly tracks: ActivityTrackRepository,
    private readonly analyses: ActivityAnalysisRepository,
    private readonly imports: ActivityImportRepository,
  ) {}

  async execute(
    viewerId: string,
    activityId: string,
    exclusions: ViewerExclusions = NO_EXCLUSIONS,
  ): Promise<ActivityDetailRecord> {
    const row = await this.visible.findRow(viewerId, activityId, exclusions);
    if (!row) {
      throw activityNotFound();
    }
    // Official values only once processed (ADR-019 §5 step 7).
    const processed = row.processingStatus === "processed";
    const [[stats], [track], analysis] = processed
      ? await Promise.all([
          this.activityStats.findByActivityIds([row.id]),
          this.tracks.findFeedFieldsByActivityIds([row.id]),
          this.analyses.findByActivityId(row.id),
        ])
      : [[], [], undefined];
    const importFormat = row.source === "imported" ? await this.imports.findFormatByActivityId(row.id) : null;
    return {
      id: row.id,
      userId: row.userId,
      sportTypeCode: row.sportTypeCode,
      visibility: row.visibility,
      processingStatus: row.processingStatus,
      startedAt: row.startedAt,
      endedAt: row.endedAt,
      title: row.title,
      description: row.description,
      source: row.source,
      importFormat,
      processingError: row.processingStatus === "failed" ? toErrorCode(row.processingError) : null,
      stats: stats
        ? {
            distanceM: stats.distanceM,
            movingTimeS: stats.movingTimeS,
            elapsedTimeS: stats.elapsedTimeS,
            elevationGainM: stats.elevationGainM,
            avgSpeedMs: stats.avgSpeedMs,
            maxSpeedMs: stats.maxSpeedMs,
            avgHeartRate: stats.avgHeartRate,
            maxHeartRate: stats.maxHeartRate,
            calories: stats.calories,
          }
        : null,
      mapPolyline: track?.mapPolyline ?? null,
      locationName: track?.locationName ?? null,
      routeTrimmed: track?.routeTrimmed ?? false,
      mediaFirst: row.mediaFirst,
      analysis: analysis?.analysis ?? null,
      updatedAt: row.updatedAt,
    };
  }
}

/** A code unknown to the contract (older or newer worker) reads as the generic `processing_error`. */
function toErrorCode(code: string | null): ActivityProcessingErrorCode {
  const parsed = activityProcessingErrorCodeSchema.safeParse(code);
  return parsed.success ? parsed.data : "processing_error";
}
