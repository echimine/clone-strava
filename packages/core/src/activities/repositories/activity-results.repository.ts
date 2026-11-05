import { Inject, Injectable } from "@nestjs/common";
import { and, asc, eq, inArray, isNull, sql } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";
import type { BestEffortResult, MedalCount } from "../domain/activity-results.js";

/** Reads « Résultats » and « Performances » of Activities (ADR-039 §3, §12), never writes. */
@Injectable()
export class ActivityResultsRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  /** A pool swim's pool length in meters, null otherwise or for an unknown Activity. */
  async findPoolLengthM(activityId: string): Promise<number | null> {
    const [row] = await this.db
      .select({ poolLengthM: schema.activity.poolLengthM })
      .from(schema.activity)
      .where(eq(schema.activity.id, activityId));
    return row?.poolLengthM ?? null;
  }

  /**
   * The Best efforts of an Activity not removed, shortest distance first, each with whether an
   * earlier one exists on the same (athlete, family, distance) and whether a faster one exists
   * (an equal time does not beat an earlier one), over the athlete's rows not removed.
   */
  findBestEfforts(activityId: string): Promise<BestEffortResult[]> {
    const own = schema.bestEffort;
    // The athlete's other rows not removed over the same (family, distance). Written out in
    // full: drizzle may leave a column of `own` unqualified, which would bind to `other`.
    const others = sql.raw(`from activities.best_effort other where other.user_id = best_effort.user_id
      and other.record_set = best_effort.record_set and other.distance_m = best_effort.distance_m
      and other.removed_at is null and other.activity_id <> best_effort.activity_id`);
    return this.db
      .select({
        distanceM: own.distanceM,
        elapsedTimeMs: own.elapsedTimeMs,
        medal: own.medal,
        isFirst: sql<boolean>`not exists (select 1 ${others}
          and other.activity_started_at < best_effort.activity_started_at)`,
        isCurrentRecord: sql<boolean>`not exists (select 1 ${others}
          and (other.elapsed_time_ms < best_effort.elapsed_time_ms
            or (other.elapsed_time_ms = best_effort.elapsed_time_ms
              and other.activity_started_at < best_effort.activity_started_at)))`,
      })
      .from(own)
      .where(and(eq(own.activityId, activityId), isNull(own.removedAt)))
      .orderBy(asc(own.distanceM));
  }

  /** Medals of the Best efforts not removed of these Activities, per Activity and Medal. */
  countMedals(activityIds: string[]): Promise<MedalCount[]> {
    if (activityIds.length === 0) {
      return Promise.resolve([]);
    }
    const effort = schema.bestEffort;
    return this.db
      .select({ activityId: effort.activityId, medal: sql<MedalCount["medal"]>`${effort.medal}`, count: sql<number>`count(*)::int` })
      .from(effort)
      .where(and(inArray(effort.activityId, activityIds), isNull(effort.removedAt), sql`${effort.medal} is not null`))
      .groupBy(effort.activityId, effort.medal);
  }
}
