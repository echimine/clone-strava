import { Inject, Injectable } from "@nestjs/common";
import { sql, type SQL } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE, type ViewerExclusions } from "../../infrastructure/index.js";

/** A Segment of the Map tab as the read gives it (ADR-039 §12). */
export interface MapSegmentRecord {
  id: string;
  sportTypeCode: string;
  name: string;
  verified: boolean;
  starred: boolean;
  distanceM: number;
  averageGradePct: number;
  climbCategory: "hc" | "1" | "2" | "3" | "4" | null;
  athleteCount: number;
  myBestTimeS: number | null;
  leaderTimeS: number | null;
  mapPolyline: string;
}

export interface MapSegmentSearch {
  viewerId: string;
  /** `[minLng, minLat, maxLng, maxLat]`. */
  bbox: [number, number, number, number];
  sportTypeCode?: string;
  favoritesOnly: boolean;
  limit: number;
}

/**
 * An Effort that stands on the Leaderboard (ADR-039 §8): of a public, processed Activity (the
 * published view `activities.leaderboard_activity`), outside its athlete's current privacy zone
 * (the published view `users.leaderboard_athlete`), not rejected. `effort` is the alias of the
 * `segment_effort` row.
 */
function standing(effort: SQL): SQL {
  return sql`${effort}.status <> 'rejected'
    and exists (
      select 1 from ${schema.leaderboardActivity} la
      where la.id = ${effort}.activity_id and la.visibility = 'public'
    )
    and exists (
      select 1 from ${schema.leaderboardAthlete} lu
      where lu.user_id = ${effort}.user_id
        and ${effort}.min_distance_to_activity_start_m >= lu.privacy_zone_radius_m
        and ${effort}.min_distance_to_activity_end_m >= lu.privacy_zone_radius_m
    )`;
}

/**
 * The Map search (ADR-039 §12): reads `segments.segment` through the GiST index on `path`, and
 * counts at read time from `segment_effort`, `segment_favorite` and the published views.
 */
@Injectable()
export class SegmentMapRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  async search(search: MapSegmentSearch, exclusions: ViewerExclusions): Promise<MapSegmentRecord[]> {
    const [minLng, minLat, maxLng, maxLat] = search.bbox;
    const zone = sql`ST_MakeEnvelope(${minLng}, ${minLat}, ${maxLng}, ${maxLat}, 4326)`;
    const e = sql.raw("e");
    const hidden = [...exclusions.hiddenAthleteIds];
    const result = await this.db.execute<{
      id: string;
      sport_type_code: string;
      name: string;
      verified: boolean;
      starred: boolean;
      distance_m: number | null;
      avg_grade: number | null;
      climb_category: MapSegmentRecord["climbCategory"];
      athlete_count: number;
      my_best_time_s: number | null;
      leader_time_s: number | null;
      map_polyline: string | null;
    }>(sql`
      select s.id, s.sport_type_code, s.name, s.verified_at is not null as verified,
        exists (
          select 1 from ${schema.segmentFavorite} f where f.segment_id = s.id and f.user_id = ${search.viewerId}
        ) as starred,
        s.distance_m, s.avg_grade, s.climb_category, s.map_polyline,
        (select count(distinct e.user_id)::int from ${schema.segmentEffort} e
          where e.segment_id = s.id and ${standing(e)}) as athlete_count,
        (select min(e.elapsed_time_s) from ${schema.segmentEffort} e
          where e.segment_id = s.id and e.user_id = ${search.viewerId} and e.status <> 'rejected') as my_best_time_s,
        (select min(e.elapsed_time_s) from ${schema.segmentEffort} e
          where e.segment_id = s.id and ${standing(e)}
            ${hidden.length === 0 ? sql`` : sql`and not (e.user_id = any(${`{${hidden.join(",")}}`}::uuid[]))`}) as leader_time_s
      from ${schema.segment} s
      where s.path && ${zone} and ST_Intersects(s.path, ${zone})
        ${search.sportTypeCode ? sql`and s.sport_type_code = ${search.sportTypeCode}` : sql``}
        ${
          search.favoritesOnly
            ? sql`and exists (select 1 from ${schema.segmentFavorite} f where f.segment_id = s.id and f.user_id = ${search.viewerId})`
            : sql``
        }
      order by athlete_count desc, s.id
      limit ${search.limit}
    `);
    return result.rows.map((row) => ({
      id: row.id,
      sportTypeCode: row.sport_type_code,
      name: row.name,
      verified: row.verified,
      starred: row.starred,
      distanceM: row.distance_m ?? 0,
      averageGradePct: row.avg_grade ?? 0,
      climbCategory: row.climb_category,
      athleteCount: row.athlete_count,
      myBestTimeS: row.my_best_time_s,
      leaderTimeS: row.my_best_time_s === null ? row.leader_time_s : null,
      mapPolyline: row.map_polyline ?? "",
    }));
  }
}
