import { Injectable } from "@nestjs/common";
import { toActivityImport } from "../domain/activity-import-record.js";
import type { AdminActivityRecord } from "../domain/admin-activity.js";
import { ActivityImportRepository } from "../repositories/activity-import.repository.js";
import { ActivityMediaRepository } from "../repositories/activity-media.repository.js";
import { ActivityStatsRepository } from "../repositories/activity-stats.repository.js";
import { ActivityRepository } from "../repositories/activity.repository.js";
import { AdminActivityRepository } from "../repositories/admin-activity.repository.js";
import { activityNotFound } from "../services/activity-not-found.js";

/**
 * `GET /v1/admin/activities/:id` (ADR-038 §11): any Activity in any state, with its official
 * values, the worker's error and attempts, the **public** trace only, its Media and its import.
 * `404 activity_not_found` for an unknown id.
 */
@Injectable()
export class GetAdminActivityUseCase {
  constructor(
    private readonly activities: ActivityRepository,
    private readonly adminActivities: AdminActivityRepository,
    private readonly activityStats: ActivityStatsRepository,
    private readonly media: ActivityMediaRepository,
    private readonly imports: ActivityImportRepository,
  ) {}

  async execute(activityId: string): Promise<AdminActivityRecord> {
    const row = await this.activities.findById(activityId);
    if (!row) {
      throw activityNotFound();
    }
    const [[stats], track, media, activityImport] = await Promise.all([
      this.activityStats.findByActivityIds([row.id]),
      this.adminActivities.findPublicTrack(row.id),
      this.media.findByActivityIds([row.id]),
      // The import id is the Activity id (ADR-028 §1).
      this.imports.findById(row.id),
    ]);
    return {
      id: row.id,
      userId: row.userId,
      title: row.title,
      description: row.description,
      sportTypeCode: row.sportTypeCode,
      processingStatus: row.processingStatus,
      source: row.source,
      visibility: row.visibility,
      processingError: row.processingError,
      processingAttempts: row.processingAttempts,
      startedAt: row.startedAt,
      endedAt: row.endedAt,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      processedAt: row.processedAt,
      distanceM: stats?.distanceM ?? null,
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
      route: track?.route ?? null,
      locationName: track?.locationName ?? null,
      media,
      import: activityImport && activityImport.userId === row.userId ? toActivityImport(activityImport) : null,
    };
  }
}
