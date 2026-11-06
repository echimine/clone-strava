import { Inject, Injectable } from "@nestjs/common";
import { sql, type SQL } from "drizzle-orm";
import type { LeaderboardGender } from "@repo/contracts";
import type { Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";
import type { LeaderboardCriteria, LeaderboardCursor } from "../domain/leaderboard-criteria.js";
import { STANDING_EFFORTS } from "./standing-effort.js";

/** One athlete's line: their best Effort that stands, ranked within the query. */
export interface LeaderboardLine {
  rank: number;
  userId: string;
  effortId: string;
  activityId: string;
  elapsedTimeS: number;
  startedAt: Date;
  /** `started_at` to the microsecond, in UTC, for the keyset cursor. */
  cursorStartedAt: string;
}

/** Who reads a Leaderboard, and whom they keep (ADR-039 §8). */
export interface LeaderboardScope {
  segmentId: string;
  gender: LeaderboardGender;
  criteria: LeaderboardCriteria;
  /** Blocks both ways and active Bans (ADR-038 §7): left out before ranking. */
  hiddenAthleteIds: readonly string[];
}

/** Rolling window of the Local Legend (ADR-039 §8). */
export const LOCAL_LEGEND_WINDOW_DAYS = 90;

const uuidArray = (ids: readonly string[]) => sql`${`{${ids.join(",")}}`}::uuid[]`;

const AGE_YEARS = sql`date_part('year', age(current_date, p.birth_date))`;

function genderCondition(gender: LeaderboardGender): SQL {
  return gender === "all" ? sql`` : sql` and p.gender = ${gender}`;
}

function criteriaCondition(criteria: LeaderboardCriteria): SQL {
  switch (criteria.kind) {
    case "none":
      return sql``;
    case "period":
      return sql` and e.started_at >= (date_trunc(${criteria.unit}, now() at time zone ${criteria.timeZone}) at time zone ${criteria.timeZone})`;
    case "following":
      return sql` and e.user_id = any(${uuidArray(criteria.athleteIds)})`;
    case "age":
      return sql` and p.birth_date is not null${
        criteria.minYears === null ? sql`` : sql` and ${AGE_YEARS} >= ${criteria.minYears}`
      }${criteria.maxYearsExclusive === null ? sql`` : sql` and ${AGE_YEARS} < ${criteria.maxYearsExclusive}`}`;
    case "weight":
      return sql` and p.weight_kg is not null${
        criteria.minKg === null ? sql`` : sql` and p.weight_kg >= ${criteria.minKg}`
      }${criteria.maxKgExclusive === null ? sql`` : sql` and p.weight_kg < ${criteria.maxKgExclusive}`}`;
  }
}

function hiddenCondition(hiddenAthleteIds: readonly string[]): SQL {
  return hiddenAthleteIds.length === 0 ? sql`` : sql` and not (e.user_id = any(${uuidArray(hiddenAthleteIds)}))`;
}

/** The ranked lines of a scope, as a CTE named `ranked`. */
function rankedLines(scope: LeaderboardScope): SQL {
  return sql`
    with standing as (
      select e.id, e.user_id, e.activity_id, e.elapsed_time_s, e.started_at
      ${STANDING_EFFORTS}
        and e.segment_id = ${scope.segmentId}
        ${genderCondition(scope.gender)}${criteriaCondition(scope.criteria)}${hiddenCondition(scope.hiddenAthleteIds)}
    ),
    lines as (
      select distinct on (user_id) id, user_id, activity_id, elapsed_time_s, started_at
      from standing
      order by user_id, elapsed_time_s, started_at, id
    ),
    ranked as (
      select *, (rank() over (order by elapsed_time_s))::int as rank from lines
    )`;
}

type LineRow = {
  rank: number;
  user_id: string;
  id: string;
  activity_id: string;
  elapsed_time_s: number;
  started_at: Date | string;
  cursor_started_at: string;
};

const LINE_COLUMNS = sql`rank, user_id, id, activity_id, elapsed_time_s, started_at,
  to_char(started_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') as cursor_started_at`;

function toLine(row: LineRow): LeaderboardLine {
  return {
    rank: row.rank,
    userId: row.user_id,
    effortId: row.id,
    activityId: row.activity_id,
    elapsedTimeS: row.elapsed_time_s,
    startedAt: new Date(row.started_at),
    cursorStartedAt: row.cursor_started_at,
  };
}

/**
 * Leaderboard reads (ADR-039 §8), computed at read time over `segments.segment_effort` and the
 * published views; nothing ranked is stored.
 */
@Injectable()
export class LeaderboardRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  /** A page of lines after `after`, in Leaderboard order. */
  async findPage(scope: LeaderboardScope, after: LeaderboardCursor | undefined, limit: number): Promise<LeaderboardLine[]> {
    const keyset = after
      ? sql`where (elapsed_time_s, started_at, id) > (${after.elapsedTimeS}, ${after.startedAt}::timestamptz, ${after.effortId}::uuid)`
      : sql``;
    const result = await this.db.execute<LineRow>(sql`${rankedLines(scope)}
      select ${LINE_COLUMNS} from ranked ${keyset}
      order by elapsed_time_s, started_at, id
      limit ${limit}`);
    return result.rows.map(toLine);
  }

  /** The viewer's line in this scope, `undefined` when they are not in it. */
  async findLineOf(scope: LeaderboardScope, userId: string): Promise<LeaderboardLine | undefined> {
    const result = await this.db.execute<LineRow>(sql`${rankedLines(scope)}
      select ${LINE_COLUMNS} from ranked where user_id = ${userId}`);
    const row = result.rows[0];
    return row ? toLine(row) : undefined;
  }

  /** Athletes with an Effort that stands, not filtered by Blocks and Bans (ADR-039 §8 counters). */
  async countAthletes(segmentId: string): Promise<number> {
    const result = await this.db.execute<{ count: number }>(sql`
      select count(distinct e.user_id)::int as count ${STANDING_EFFORTS} and e.segment_id = ${segmentId}`);
    return result.rows[0]?.count ?? 0;
  }

  /**
   * The Local Legend (ADR-039 §8): most Efforts that stand over the last 90 rolling days, one per
   * Activity; on an equal count, whoever reached it first. After the viewer filter.
   */
  async findLocalLegend(
    segmentId: string,
    gender: LeaderboardGender,
    hiddenAthleteIds: readonly string[],
  ): Promise<{ userId: string; effortCount: number } | undefined> {
    return (await this.findLocalLegends([segmentId], gender, hiddenAthleteIds)).get(segmentId);
  }

  /** The Local Legend of each of `segmentIds` that has one, in one query (the « Résultats » crowns). */
  async findLocalLegends(
    segmentIds: readonly string[],
    gender: LeaderboardGender,
    hiddenAthleteIds: readonly string[],
  ): Promise<Map<string, { userId: string; effortCount: number }>> {
    if (segmentIds.length === 0) {
      return new Map();
    }
    const result = await this.db.execute<{ segment_id: string; user_id: string; effort_count: number }>(sql`
      with per_activity as (
        select e.segment_id, e.user_id, e.activity_id, min(e.started_at) as started_at
        ${STANDING_EFFORTS}
          and e.segment_id = any(${uuidArray(segmentIds)})
          and e.started_at >= now() - make_interval(days => ${LOCAL_LEGEND_WINDOW_DAYS})
          ${genderCondition(gender)}${hiddenCondition(hiddenAthleteIds)}
        group by e.segment_id, e.user_id, e.activity_id
      ),
      counts as (
        select segment_id, user_id, count(*)::int as effort_count, max(started_at) as reached_at
        from per_activity
        group by segment_id, user_id
      )
      select distinct on (segment_id) segment_id, user_id, effort_count
      from counts
      order by segment_id, effort_count desc, reached_at, user_id`);
    return new Map(
      result.rows.map((row) => [row.segment_id, { userId: row.user_id, effortCount: row.effort_count }]),
    );
  }

  /**
   * The athlete's own count over the Local Legend window, one per Activity, in the same sex as the
   * Local Legend shown; `null` when the athlete is not of that sex.
   */
  async countLocalLegendEfforts(segmentId: string, userId: string, gender: LeaderboardGender): Promise<number | null> {
    const inScope =
      gender === "all" ? sql`true` : sql`exists (select 1 from users.leaderboard_athlete where user_id = ${userId} and gender = ${gender})`;
    const result = await this.db.execute<{ count: number; in_scope: boolean }>(sql`
      select count(distinct e.activity_id)::int as count, ${inScope} as in_scope
      ${STANDING_EFFORTS}
        and e.segment_id = ${segmentId}
        and e.user_id = ${userId}
        and e.started_at >= now() - make_interval(days => ${LOCAL_LEGEND_WINDOW_DAYS})`);
    const row = result.rows[0];
    return row?.in_scope ? row.count : null;
  }
}
