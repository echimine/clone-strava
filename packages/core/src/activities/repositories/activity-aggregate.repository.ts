import { Inject, Injectable } from "@nestjs/common";
import { and, asc, desc, eq, inArray, sql, type SQL } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";
import { ATHLETE_TIME_ZONE, type WeekTotals } from "../domain/athlete-weeks.js";

type Visibility = (typeof schema.activityVisibilityEnum.enumValues)[number];

/** Whose Activities are aggregated, and which of them the viewer may see (ADR-036 §3). */
export interface AggregateScope {
  userId: string;
  visibilities: readonly Visibility[];
  /** Omitted: all sports. */
  sportTypeCode?: string;
}

/** Totals of a set of Activities; a stat not computed counts as 0. */
export interface ActivityTotals {
  activityCount: number;
  distanceM: number;
  movingTimeS: number;
  elevationGainM: number;
}

/** Calendar date range in `ATHLETE_TIME_ZONE`, `YYYY-MM-DD`: `from` included, `to` excluded. */
export interface LocalDateRange {
  from?: string;
  to?: string;
}

// Inlined constant, not a bind parameter: `GROUP BY` must match the selected expression exactly,
// and two parameters are two different expressions to Postgres.
const timeZone = sql.raw(`'${ATHLETE_TIME_ZONE}'`);
const localDate = sql`(${schema.activity.startedAt} at time zone ${timeZone})::date`;
// `date_trunc('week', …)` starts weeks on Monday (ISO).
const weekStart = sql`date_trunc('week', ${schema.activity.startedAt} at time zone ${timeZone})::date`;
const totalsColumns = {
  activityCount: sql<number>`count(*)::int`,
  distanceM: sql<number>`coalesce(sum(${schema.activityStats.distanceM}::float8), 0)::float8`,
  movingTimeS: sql<number>`coalesce(sum(${schema.activityStats.movingTimeS}), 0)::float8`,
  elevationGainM: sql<number>`coalesce(sum(${schema.activityStats.elevationGainM}::float8), 0)::float8`,
};

/**
 * Aggregates over `activities.activity` + `activity_stats` (ADR-036 §4): processed Activities of
 * one athlete, grouped in SQL by `ATHLETE_TIME_ZONE` calendar days and Monday weeks. No
 * denormalised counters.
 */
@Injectable()
export class ActivityAggregateRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  /** One row per week (from the week of `range.from`) that has at least one Activity. */
  async findWeeklyTotals(scope: AggregateScope, range: LocalDateRange): Promise<WeekTotals[]> {
    const rows = await this.db
      .select({ weekStart: sql<string>`to_char(${weekStart}, 'YYYY-MM-DD')`, ...totalsColumns })
      .from(schema.activity)
      .leftJoin(schema.activityStats, eq(schema.activityStats.activityId, schema.activity.id))
      .where(where(scope, range))
      .groupBy(weekStart);
    return rows.map((row) => ({ ...row, ...numbers(row) }));
  }

  /** The Mondays of every week with an Activity, newest first. */
  async findActiveWeekStarts(scope: AggregateScope): Promise<string[]> {
    const rows = await this.db
      .selectDistinct({ weekStart: sql<string>`to_char(${weekStart}, 'YYYY-MM-DD')` })
      .from(schema.activity)
      .where(where(scope, {}));
    return rows.map((row) => row.weekStart).sort().reverse();
  }

  /** The number of Activities of each sport, most first (ties by sport code). */
  async findCountsBySport(scope: AggregateScope): Promise<{ sportTypeCode: string; activityCount: number }[]> {
    const activityCount = sql<number>`count(*)::int`;
    const rows = await this.db
      .select({ sportTypeCode: schema.activity.sportTypeCode, activityCount })
      .from(schema.activity)
      .where(where(scope, {}))
      .groupBy(schema.activity.sportTypeCode)
      .orderBy(desc(activityCount), asc(schema.activity.sportTypeCode));
    return rows.map((row) => ({ sportTypeCode: row.sportTypeCode, activityCount: Number(row.activityCount) }));
  }

  /** The calendar days of `range` with an Activity, oldest first. */
  async findActiveDays(scope: AggregateScope, range: LocalDateRange): Promise<string[]> {
    const rows = await this.db
      .selectDistinct({ day: sql<string>`to_char(${localDate}, 'YYYY-MM-DD')` })
      .from(schema.activity)
      .where(where(scope, range));
    return rows.map((row) => row.day).sort();
  }

  async findTotals(scope: AggregateScope, range: LocalDateRange): Promise<ActivityTotals> {
    const [row] = await this.db
      .select(totalsColumns)
      .from(schema.activity)
      .leftJoin(schema.activityStats, eq(schema.activityStats.activityId, schema.activity.id))
      .where(where(scope, range));
    return row ? numbers(row) : { activityCount: 0, distanceM: 0, movingTimeS: 0, elevationGainM: 0 };
  }
}

function where(scope: AggregateScope, range: LocalDateRange): SQL | undefined {
  return and(
    eq(schema.activity.userId, scope.userId),
    eq(schema.activity.processingStatus, "processed"),
    inArray(schema.activity.visibility, [...scope.visibilities]),
    scope.sportTypeCode ? eq(schema.activity.sportTypeCode, scope.sportTypeCode) : undefined,
    range.from ? sql`${localDate} >= ${range.from}::date` : undefined,
    range.to ? sql`${localDate} < ${range.to}::date` : undefined,
  );
}

/** `pg` returns `float8` as numbers but be explicit: the driver may hand strings for numerics. */
function numbers(row: ActivityTotals): ActivityTotals {
  return {
    activityCount: Number(row.activityCount),
    distanceM: Number(row.distanceM),
    movingTimeS: Number(row.movingTimeS),
    elevationGainM: Number(row.elevationGainM),
  };
}
