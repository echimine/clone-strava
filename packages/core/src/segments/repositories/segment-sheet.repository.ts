import { Inject, Injectable } from "@nestjs/common";
import { sql } from "drizzle-orm";
import type { Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";
import { DEFAULT_PRIVACY_ZONE_RADIUS_M } from "../domain/segment-sports.js";

/** A Segment as its sheet reads it (ADR-039 §12), for one viewer. */
export interface SegmentSheetRow {
  id: string;
  name: string;
  sportTypeCode: string;
  createdBy: string | null;
  origin: "athlete" | "nervo";
  verified: boolean;
  distanceM: number | null;
  elevationGainM: number | null;
  avgGrade: number | null;
  maxGrade: number | null;
  climbCategory: "hc" | "1" | "2" | "3" | "4" | null;
  /** `[lon, lat, altitude]` per point of the LineStringZ; empty without a path. */
  coordinates: number[][];
  historyMatched: boolean;
  favoriteCount: number;
  starred: boolean;
  /** Someone other than the creator has an Effort on it (ADR-039 §5: deletion refused). */
  hasOthersEfforts: boolean;
}

/** One of the viewer's Efforts on the Segment, with whether it stands (ADR-039 §8). */
export interface ViewerEffortRow {
  id: string;
  activityId: string;
  activityVisibility: "public" | "followers" | "private";
  startedAt: Date;
  elapsedTimeS: number;
  medal: "gold" | "silver" | "bronze" | null;
  status: "valid" | "suspicious" | "rejected";
  standing: boolean;
}

const RADIUS = sql.raw(`coalesce(p.privacy_zone_radius_m, ${DEFAULT_PRIVACY_ZONE_RADIUS_M})`);

/** The sheet's reads on `segments` (ADR-039 §12), joining only the published views. */
@Injectable()
export class SegmentSheetRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  async exists(segmentId: string): Promise<boolean> {
    const result = await this.db.execute(sql`select 1 from segments.segment where id = ${segmentId}`);
    return result.rows.length > 0;
  }

  /** What a Report copies of a Segment (ADR-039 §11): its name, and its creator if any. */
  async findReportTarget(segmentId: string): Promise<{ name: string; createdBy: string | null } | undefined> {
    const result = await this.db.execute<{ name: string; created_by: string | null }>(
      sql`select name, created_by from segments.segment where id = ${segmentId}`,
    );
    const row = result.rows[0];
    return row ? { name: row.name, createdBy: row.created_by } : undefined;
  }

  async findForViewer(segmentId: string, viewerId: string): Promise<SegmentSheetRow | undefined> {
    const result = await this.db.execute<{
      id: string;
      name: string;
      sport_type_code: string;
      created_by: string | null;
      origin: "athlete" | "nervo";
      verified: boolean;
      distance_m: number | null;
      elevation_gain_m: number | null;
      avg_grade: number | null;
      max_grade: number | null;
      climb_category: SegmentSheetRow["climbCategory"];
      path: string | null;
      history_matched: boolean;
      favorite_count: number;
      starred: boolean;
      has_others_efforts: boolean;
    }>(sql`
      select s.id, s.name, s.sport_type_code, s.created_by, s.origin, s.verified_at is not null as verified,
             s.distance_m, s.elevation_gain_m, s.avg_grade, s.max_grade, s.climb_category,
             ST_AsGeoJSON(s.path) as path, s.history_matched_at is not null as history_matched,
             (select count(*)::int from segments.segment_favorite f where f.segment_id = s.id) as favorite_count,
             exists (select 1 from segments.segment_favorite f where f.segment_id = s.id and f.user_id = ${viewerId}) as starred,
             exists (select 1 from segments.segment_effort e
                      where e.segment_id = s.id and e.user_id is distinct from s.created_by) as has_others_efforts
      from segments.segment s
      where s.id = ${segmentId}`);
    const row = result.rows[0];
    if (!row) {
      return undefined;
    }
    return {
      id: row.id,
      name: row.name,
      sportTypeCode: row.sport_type_code,
      createdBy: row.created_by,
      origin: row.origin,
      verified: row.verified,
      distanceM: row.distance_m,
      elevationGainM: row.elevation_gain_m,
      avgGrade: row.avg_grade,
      maxGrade: row.max_grade,
      climbCategory: row.climb_category,
      coordinates: row.path ? (JSON.parse(row.path) as { coordinates: number[][] }).coordinates : [],
      historyMatched: row.history_matched,
      favoriteCount: row.favorite_count,
      starred: row.starred,
      hasOthersEfforts: row.has_others_efforts,
    };
  }

  /** Every Effort of the viewer on the Segment, newest first, whatever the visibility. */
  async findViewerEfforts(segmentId: string, viewerId: string): Promise<ViewerEffortRow[]> {
    const result = await this.db.execute<{
      id: string;
      activity_id: string;
      visibility: ViewerEffortRow["activityVisibility"];
      started_at: Date | string;
      elapsed_time_s: number;
      medal: ViewerEffortRow["medal"];
      status: ViewerEffortRow["status"];
      standing: boolean;
    }>(sql`
      select e.id, e.activity_id, a.visibility, e.started_at, e.elapsed_time_s, e.medal, e.status,
             (a.visibility = 'public' and e.status <> 'rejected'
              and e.min_distance_to_activity_start_m >= ${RADIUS}
              and e.min_distance_to_activity_end_m >= ${RADIUS}) as standing
      from segments.segment_effort e
      join activities.leaderboard_activity a on a.id = e.activity_id
      left join users.leaderboard_athlete p on p.user_id = e.user_id
      where e.segment_id = ${segmentId} and e.user_id = ${viewerId}
      order by e.started_at desc, e.id`);
    return result.rows.map((row) => ({
      id: row.id,
      activityId: row.activity_id,
      activityVisibility: row.visibility,
      startedAt: new Date(row.started_at),
      elapsedTimeS: row.elapsed_time_s,
      medal: row.medal,
      status: row.status,
      standing: row.standing,
    }));
  }
}
