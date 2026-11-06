import { Inject, Injectable } from "@nestjs/common";
import { and, asc, eq, gt, ne, sql } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";
import {
  marginInDegrees,
  type ActivitiesNearPathPage,
  type ActivitiesNearPathQuery,
} from "../domain/matching-trace.js";

/**
 * Processed Activities whose stored route passes near a path's start and end (ADR-039 §6, §7):
 * an indexed prefilter in degrees (`activity_track_route_gist_idx`); reads `activity` and
 * `activity_track` only (ADR-021 §6).
 */
@Injectable()
export class ActivitiesNearPathRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  async findPage(query: ActivitiesNearPathQuery): Promise<ActivitiesNearPathPage> {
    const { activity, activityTrack } = schema;
    const marginDeg = marginInDegrees(query.marginM, [query.start.lat, query.end.lat]);
    const near = (point: { lat: number; lon: number }) =>
      sql`ST_DWithin(${activityTrack.route}, ST_SetSRID(ST_MakePoint(${point.lon}, ${point.lat}), 4326), ${marginDeg})`;
    const rows = await this.db
      .select({ id: activity.id, userId: activity.userId })
      .from(activity)
      .innerJoin(activityTrack, eq(activityTrack.activityId, activity.id))
      .where(
        and(
          eq(activity.sportTypeCode, query.sportTypeCode),
          eq(activity.processingStatus, "processed"),
          near(query.start),
          near(query.end),
          query.cursor ? gt(activity.id, query.cursor) : undefined,
          query.userId ? eq(activity.userId, query.userId) : undefined,
          query.excludeUserId ? ne(activity.userId, query.excludeUserId) : undefined,
        ),
      )
      .orderBy(asc(activity.id))
      .limit(query.limit);
    return {
      activities: rows,
      nextCursor: rows.length === query.limit ? rows.at(-1)!.id : null,
    };
  }
}
