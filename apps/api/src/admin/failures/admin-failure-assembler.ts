import { Injectable } from "@nestjs/common";
import type {
  AdminFailedActivityListResponse,
  AdminFailedImportListResponse,
  AdminStaleActivityListResponse,
  AdminFailureListQuery,
} from "@repo/contracts";
import { ActivitiesService } from "@repo/core/activities";
import { AthleteIdentities } from "../../identities/athlete-identities.js";

/**
 * The "Échecs" tab of the Jobs screen (ADR-038 §14): the failures from `activities`, the
 * athletes' names and Avatars from `users`/`auth`, one batch call each.
 */
@Injectable()
export class AdminFailureAssembler {
  constructor(
    private readonly activities: ActivitiesService,
    private readonly identities: AthleteIdentities,
  ) {}

  async activitiesPage(query: AdminFailureListQuery): Promise<AdminFailedActivityListResponse> {
    const { rows, total } = await this.activities.listFailedForAdmin(query);
    const athlete = await this.identities.resolve(rows.map((row) => row.userId));
    return {
      items: rows.map((row) => ({
        id: row.id,
        title: row.title,
        athlete: athlete(row.userId),
        sportTypeCode: row.sportTypeCode,
        processingError: row.processingError,
        processingAttempts: row.processingAttempts,
        startedAt: row.startedAt.toISOString(),
        createdAt: row.createdAt.toISOString(),
      })),
      total,
      page: query.page,
      pageSize: query.pageSize,
    };
  }

  async importsPage(query: AdminFailureListQuery): Promise<AdminFailedImportListResponse> {
    const { rows, total } = await this.activities.listFailedImportsForAdmin(query);
    const athlete = await this.identities.resolve(rows.map((row) => row.userId));
    return {
      items: rows.map((row) => ({
        id: row.id,
        athlete: athlete(row.userId),
        format: row.format,
        fileName: row.fileName,
        error: row.error,
        attempts: row.attempts,
        createdAt: row.createdAt.toISOString(),
        processedAt: row.processedAt?.toISOString() ?? null,
      })),
      total,
      page: query.page,
      pageSize: query.pageSize,
    };
  }

  async recomputesPage(query: AdminFailureListQuery): Promise<AdminStaleActivityListResponse> {
    const { rows, total } = await this.activities.listStaleForAdmin(query);
    const athlete = await this.identities.resolve(rows.map((row) => row.userId));
    return {
      items: rows.map((row) => ({
        id: row.id,
        title: row.title,
        athlete: athlete(row.userId),
        sportTypeCode: row.sportTypeCode,
        computedForSportTypeCode: row.computedForSportTypeCode,
        startedAt: row.startedAt.toISOString(),
        updatedAt: row.updatedAt.toISOString(),
      })),
      total,
      page: query.page,
      pageSize: query.pageSize,
    };
  }
}
