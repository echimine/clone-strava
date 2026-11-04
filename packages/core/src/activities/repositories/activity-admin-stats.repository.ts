import { Inject, Injectable } from "@nestjs/common";
import { and, count, countDistinct, eq, gte, sql } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import {
  countsByDay,
  DATABASE,
  notByUsers,
  parisDay,
  withinRange,
  type InstantRange,
} from "../../infrastructure/index.js";
import type { ActivityFailureCounts, ActivityGrowthCounts } from "../domain/activity-admin-stats.js";

/**
 * Backoffice dashboard counts (ADR-038 §15) over `activity`, `activity_import` and
 * `activity_media`: aggregates computed on the fly. An Activity's date is `started_at`, never
 * `created_at`.
 */
@Injectable()
export class ActivityAdminStatsRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  /** "À traiter": failed Activities (all), imports failed since `failedImportsSince`, not by `excludedUserIds`. */
  async countFailures(failedImportsSince: Date, excludedUserIds: readonly string[]): Promise<ActivityFailureCounts> {
    const [activities] = await this.db
      .select({ total: count() })
      .from(schema.activity)
      .where(and(eq(schema.activity.processingStatus, "failed"), notByUsers(schema.activity.userId, excludedUserIds)));
    const [imports] = await this.db
      .select({ total: count() })
      .from(schema.activityImport)
      .where(
        and(
          eq(schema.activityImport.status, "failed"),
          gte(schema.activityImport.processedAt, failedImportsSince),
          notByUsers(schema.activityImport.userId, excludedUserIds),
        ),
      );
    return { failedActivities: activities?.total ?? 0, failedImports: imports?.total ?? 0 };
  }

  /** "Croissance": Activities started in `range` by source, their athletes, Media added. */
  async countGrowth(range: InstantRange, excludedUserIds: readonly string[]): Promise<ActivityGrowthCounts> {
    const activity = schema.activity;
    const [started] = await this.db
      .select({
        recorded: sql<number>`count(*) filter (where ${activity.source} = 'recorded')`.mapWith(Number),
        imported: sql<number>`count(*) filter (where ${activity.source} = 'imported')`.mapWith(Number),
        manual: sql<number>`count(*) filter (where ${activity.source} = 'manual')`.mapWith(Number),
        athletes: countDistinct(activity.userId),
      })
      .from(activity)
      .where(and(withinRange(activity.startedAt, range), notByUsers(activity.userId, excludedUserIds)));
    const [media] = await this.db
      .select({ total: count() })
      .from(schema.activityMedia)
      .innerJoin(activity, eq(activity.id, schema.activityMedia.activityId))
      .where(and(withinRange(schema.activityMedia.createdAt, range), notByUsers(activity.userId, excludedUserIds)));
    return {
      recorded: started?.recorded ?? 0,
      imported: started?.imported ?? 0,
      manual: started?.manual ?? 0,
      activeAthletes: started?.athletes ?? 0,
      media: media?.total ?? 0,
    };
  }

  /** Activities started per Paris day of `range` (days without any are absent). */
  async countStartedPerParisDay(range: InstantRange, excludedUserIds: readonly string[]): Promise<Map<string, number>> {
    const day = parisDay(schema.activity.startedAt);
    const rows = await this.db
      .select({ day, total: count() })
      .from(schema.activity)
      .where(and(withinRange(schema.activity.startedAt, range), notByUsers(schema.activity.userId, excludedUserIds)))
      .groupBy(day);
    return countsByDay(rows);
  }
}
