import { Injectable, NotFoundException } from "@nestjs/common";
import {
  activityProcessingErrorCodeSchema,
  type ActivityDetail,
  type ActivityProcessingErrorCode,
} from "@repo/contracts";
import { ActivityRepository } from "../repositories/activity.repository.js";
import { ActivityStatsRepository } from "../repositories/activity-stats.repository.js";

/**
 * `GET /v1/activities/:id` (ADR-031 §13, amends ADR-019 §9): the author
 * reloads their activity whatever its state. Anyone else gets `404`,
 * without learning that the id exists.
 */
@Injectable()
export class GetOwnActivityUseCase {
  constructor(
    private readonly activities: ActivityRepository,
    private readonly activityStats: ActivityStatsRepository,
  ) {}

  async execute(userId: string, activityId: string): Promise<ActivityDetail> {
    const row = await this.activities.findById(activityId);
    if (!row || row.userId !== userId) {
      throw new NotFoundException({ code: "not_found", message: "Activity not found" });
    }
    // Official values only once processed (ADR-019 §5 step 7).
    const [stats] =
      row.processingStatus === "processed" ? await this.activityStats.findByActivityIds([row.id]) : [];
    return {
      id: row.id,
      sportTypeCode: row.sportTypeCode,
      title: row.title,
      description: row.description ?? undefined,
      startedAt: row.startedAt.toISOString(),
      endedAt: row.endedAt.toISOString(),
      visibility: row.visibility,
      processingStatus: row.processingStatus,
      processingError: row.processingStatus === "failed" ? toErrorCode(row.processingError) : undefined,
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
          }
        : null,
    };
  }
}

/** A code unknown to the contract (older or newer worker) reads as the generic `processing_error`. */
function toErrorCode(code: string | null): ActivityProcessingErrorCode {
  const parsed = activityProcessingErrorCodeSchema.safeParse(code);
  return parsed.success ? parsed.data : "processing_error";
}
