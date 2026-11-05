import { Inject, Injectable } from "@nestjs/common";
import { and, asc, eq, inArray, ne, or, sql, type SQL } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";
import type { EffortMedalCount } from "../domain/effort-result.js";
import type { Medal } from "../domain/segment-medals.js";
import { DEFAULT_PRIVACY_ZONE_RADIUS_M } from "../domain/segment-sports.js";

/** An Effort row of « Résultats » before the Local Legend is known. */
export interface EffortResultRow {
  id: string;
  userId: string;
  segmentId: string;
  segmentName: string;
  segmentDistanceM: number;
  verified: boolean;
  elapsedTimeS: number;
  medal: Medal | null;
  isFirstPass: boolean;
  startLat: number;
  startLon: number;
}

const effort = schema.segmentEffort;
const athlete = schema.leaderboardAthlete;

/**
 * An Effort the viewer may see (ADR-039 §8): not rejected, and outside its athlete's privacy zone
 * unless the viewer is that athlete. The radius is read now from the published view
 * `users.leaderboard_athlete`, so a changed radius applies at once.
 */
function visibleTo(viewerId: string): SQL {
  const radius = sql`coalesce(${athlete.privacyZoneRadiusM}, ${DEFAULT_PRIVACY_ZONE_RADIUS_M})`;
  return and(
    ne(effort.status, "rejected"),
    or(
      eq(effort.userId, viewerId),
      and(
        sql`${effort.minDistanceToActivityStartM} >= ${radius}`,
        sql`${effort.minDistanceToActivityEndM} >= ${radius}`,
      ),
    ),
  )!;
}

/**
 * Reads an Activity's Efforts for « Résultats » and « Performances » (ADR-039 §12), joined
 * read-only with the published views (ADR-021 §7 amended). Never writes.
 */
@Injectable()
export class EffortResultsRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  /** The Efforts of an Activity the viewer may see, in trace order. */
  findByActivity(activityId: string, viewerId: string): Promise<EffortResultRow[]> {
    const segment = schema.segment;
    const start = sql`coalesce(${segment.startPoint}, ST_StartPoint(${segment.path}))`;
    return this.db
      .select({
        id: effort.id,
        userId: effort.userId,
        segmentId: segment.id,
        segmentName: segment.name,
        segmentDistanceM: sql<number>`coalesce(${segment.distanceM}, ST_Length(${segment.path}::geography))::float8`,
        verified: sql<boolean>`${segment.verifiedAt} is not null`,
        elapsedTimeS: effort.elapsedTimeS,
        medal: effort.medal,
        // Written out in full: drizzle may leave an outer column unqualified, binding it to `earlier`.
        isFirstPass: sql<boolean>`not exists (select 1 from segments.segment_effort earlier
          where earlier.user_id = segment_effort.user_id and earlier.segment_id = segment_effort.segment_id
            and earlier.status <> 'rejected' and earlier.started_at < segment_effort.started_at)`,
        startLat: sql<number>`ST_Y(${start})`,
        startLon: sql<number>`ST_X(${start})`,
      })
      .from(effort)
      .innerJoin(segment, eq(segment.id, effort.segmentId))
      .leftJoin(athlete, eq(athlete.userId, effort.userId))
      .where(and(eq(effort.activityId, activityId), visibleTo(viewerId)))
      .orderBy(asc(effort.startIndex), asc(effort.id));
  }

  /** The Medals of the Efforts of these Activities the viewer may see, per Activity and Medal. */
  countMedals(activityIds: string[], viewerId: string): Promise<EffortMedalCount[]> {
    if (activityIds.length === 0) {
      return Promise.resolve([]);
    }
    return this.db
      .select({
        activityId: effort.activityId,
        medal: sql<Medal>`${effort.medal}`,
        count: sql<number>`count(*)::int`,
      })
      .from(effort)
      .leftJoin(athlete, eq(athlete.userId, effort.userId))
      .where(and(inArray(effort.activityId, activityIds), sql`${effort.medal} is not null`, visibleTo(viewerId)))
      .groupBy(effort.activityId, effort.medal);
  }

  /**
   * The Segments are still being looked for (ADR-039 §12): the Activity is processed and has no
   * `activity_matching` row, or one with an older version.
   */
  async isMatchingInProgress(activityId: string, version: number): Promise<boolean> {
    const view = schema.leaderboardActivity;
    const matching = schema.activityMatching;
    const [row] = await this.db
      .select({ version: matching.version })
      .from(view)
      .leftJoin(matching, eq(matching.activityId, view.id))
      .where(eq(view.id, activityId));
    return row !== undefined && (row.version === null || row.version < version);
  }
}
