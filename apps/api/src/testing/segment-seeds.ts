import type { AthleteApp } from "./athlete-app.js";

/** Climbs 100 m north of Annecy over ~1.1 km: three points of a LineStringZ. */
const PATH = "SRID=4326;LINESTRING Z(6.12 45.9 500, 6.12 45.905 550, 6.12 45.91 600)";

export interface EffortSeed {
  elapsedTimeS: number;
  startedAt?: string;
  /** Visibility of the Effort's own Activity (created for it). */
  visibility?: "public" | "followers" | "private";
  status?: "valid" | "suspicious" | "rejected";
  medal?: "gold" | "silver" | "bronze" | null;
  /** Crow-fly distances to the Activity's first and last points (privacy zone, ADR-039 §6). */
  toStartM?: number;
  toEndM?: number;
  /** Reuses an Activity (several Efforts in one Activity). */
  activityId?: string;
}

export interface SegmentSeeds {
  /** A Segment (athlete origin, history matched unless said otherwise); returns its id. */
  segment: (options?: {
    name?: string;
    createdBy?: string | null;
    verified?: boolean;
    historyMatched?: boolean;
    climbCategory?: string | null;
  }) => Promise<string>;
  /** An Effort on its own processed Activity; returns `{ effortId, activityId }`. */
  effort: (segmentId: string, userId: string, effort: EffortSeed) => Promise<{ effortId: string; activityId: string }>;
  favorite: (segmentId: string, userId: string) => Promise<void>;
  premium: (userId: string) => Promise<void>;
  profile: (userId: string, values: { gender?: string; birthDate?: string; weightKg?: number; radiusM?: number }) => Promise<void>;
}

/** SQL seeds for the Segment sheet and Leaderboard specs (ADR-039 §8, §12). */
export function segmentSeeds(api: AthleteApp): SegmentSeeds {
  return {
    segment: async (options = {}) => {
      const [row] = await api.sql<{ id: string }>(
        `insert into segments.segment
           (name, sport_type_code, created_by, verified_at, path, start_point, end_point, distance_m, avg_grade,
            max_grade, elevation_gain_m, min_altitude_m, max_altitude_m, climb_category, history_matched_at)
         values ($1, 'run', $2, $3, ST_GeomFromEWKT($4), ST_StartPoint(ST_Force2D(ST_GeomFromEWKT($4))),
                 ST_EndPoint(ST_Force2D(ST_GeomFromEWKT($4))), 1112, 9, 10.2, 100, 500, 600, $5, $6)
         returning id`,
        [
          options.name ?? "Montée du test",
          options.createdBy ?? null,
          options.verified ? new Date() : null,
          PATH,
          options.climbCategory === undefined ? "4" : options.climbCategory,
          options.historyMatched === false ? null : new Date(),
        ],
      );
      return row!.id;
    },
    effort: async (segmentId, userId, effort) => {
      const activityId = effort.activityId ?? (await api.seedActivity(userId, { visibility: effort.visibility ?? "public" }));
      const [row] = await api.sql<{ id: string }>(
        `insert into segments.segment_effort
           (activity_id, segment_id, user_id, elapsed_time_s, started_at, start_index, end_index,
            min_distance_to_activity_start_m, min_distance_to_activity_end_m, status, medal)
         values ($1, $2, $3, $4, $5,
                 (select coalesce(max(start_index), 0) + 10 from segments.segment_effort where activity_id = $1),
                 1000, $6, $7, $8, $9)
         returning id`,
        [
          activityId,
          segmentId,
          userId,
          effort.elapsedTimeS,
          effort.startedAt ?? new Date(Date.now() - 86_400_000).toISOString(),
          effort.toStartM ?? 5_000,
          effort.toEndM ?? 5_000,
          effort.status ?? "valid",
          effort.medal ?? null,
        ],
      );
      return { effortId: row!.id, activityId };
    },
    favorite: async (segmentId, userId) => {
      await api.sql("insert into segments.segment_favorite (user_id, segment_id) values ($1, $2)", [userId, segmentId]);
    },
    premium: async (userId) => {
      await api.sql(
        `insert into subscriptions.user_subscription (user_id, is_active, store, expires_at, will_renew)
         values ($1, true, 'app_store', now() + interval '30 days', true)`,
        [userId],
      );
    },
    profile: async (userId, values) => {
      await api.sql(
        `update users.user_profile
            set gender = coalesce($2, gender), birth_date = coalesce($3::date, birth_date),
                weight_kg = coalesce($4, weight_kg), privacy_zone_radius_m = coalesce($5, privacy_zone_radius_m)
          where user_id = $1`,
        [userId, values.gender ?? null, values.birthDate ?? null, values.weightKg ?? null, values.radiusM ?? null],
      );
    },
  };
}
