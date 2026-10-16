import { Injectable, NotFoundException } from "@nestjs/common";
import { activityProcessingErrorCodeSchema, type ActivityProcessingErrorCode } from "@repo/contracts";
import { ActivityStatsRepository } from "../repositories/activity-stats.repository.js";
import { ActivityTrackRepository } from "../repositories/activity-track.repository.js";
import type { ActivityDetailRecord } from "../domain/activity-detail.js";
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
  ) {}

  async execute(viewerId: string, activityId: string): Promise<ActivityDetailRecord> {
    const row = await this.visible.findRow(viewerId, activityId);
    if (!row) {
      throw new NotFoundException({ code: "activity_not_found", message: "Activity not found" });
    }
    // Official values only once processed (ADR-019 §5 step 7).
    const processed = row.processingStatus === "processed";
    const [[stats], [track]] = processed
      ? await Promise.all([
          this.activityStats.findByActivityIds([row.id]),
          this.tracks.findFeedFieldsByActivityIds([row.id]),
        ])
      : [[], []];
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
      updatedAt: row.updatedAt,
    };
  }
}

/** A code unknown to the contract (older or newer worker) reads as the generic `processing_error`. */
function toErrorCode(code: string | null): ActivityProcessingErrorCode {
  const parsed = activityProcessingErrorCodeSchema.safeParse(code);
  return parsed.success ? parsed.data : "processing_error";
}
