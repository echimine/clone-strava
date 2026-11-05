import { Inject, Injectable } from "@nestjs/common";
import { and, asc, eq, inArray, isNull, sql } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE, type DbExecutor } from "../../infrastructure/index.js";
import type { RecordSet } from "../domain/best-efforts.js";
import type { Medal } from "../domain/medals.js";

type BestEffortRow = typeof schema.bestEffort.$inferSelect;

/** Reads and writes on `activities.best_effort` only (ADR-021 §6, ADR-039 §17). */
@Injectable()
export class BestEffortRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  /**
   * Serialises the writes on one athlete's Best efforts until the end of the transaction, so
   * two replays of their Medals never interleave. Always taken after any `activity` row lock.
   */
  async lockAthlete(userId: string, tx: DbExecutor): Promise<void> {
    await tx.execute(sql`select pg_advisory_xact_lock(hashtextextended(${`best_effort:${userId}`}, 0))`);
  }

  /** Every row of an Activity, removed ones included, shortest distance first. */
  findByActivity(activityId: string, executor: DbExecutor = this.db): Promise<BestEffortRow[]> {
    return executor
      .select()
      .from(schema.bestEffort)
      .where(eq(schema.bestEffort.activityId, activityId))
      .orderBy(asc(schema.bestEffort.distanceM));
  }

  /**
   * Upserts the rows of an Activity: the time, its start and the family are updated, never
   * `removed_at` (a removed row stays removed) nor `medal` (replayed afterwards).
   */
  async upsert(rows: Array<typeof schema.bestEffort.$inferInsert>, tx: DbExecutor): Promise<void> {
    if (rows.length === 0) {
      return;
    }
    await tx
      .insert(schema.bestEffort)
      .values(rows)
      .onConflictDoUpdate({
        target: [schema.bestEffort.activityId, schema.bestEffort.distanceM],
        set: {
          recordSet: sql`excluded.record_set`,
          elapsedTimeMs: sql`excluded.elapsed_time_ms`,
          startDistanceM: sql`excluded.start_distance_m`,
          activityStartedAt: sql`excluded.activity_started_at`,
        },
      });
  }

  /** Deletes the rows of an Activity over these distances. */
  async deleteDistances(activityId: string, distancesM: number[], tx: DbExecutor): Promise<void> {
    if (distancesM.length === 0) {
      return;
    }
    await tx
      .delete(schema.bestEffort)
      .where(and(eq(schema.bestEffort.activityId, activityId), inArray(schema.bestEffort.distanceM, distancesM)));
  }

  /** Every time of an athlete on one (family, distance), removed ones included: the Medals' input. */
  findTimes(userId: string, recordSet: RecordSet, distanceM: number, tx: DbExecutor) {
    return tx
      .select({
        activityId: schema.bestEffort.activityId,
        activityStartedAt: schema.bestEffort.activityStartedAt,
        elapsedTimeMs: schema.bestEffort.elapsedTimeMs,
        removedAt: schema.bestEffort.removedAt,
        medal: schema.bestEffort.medal,
      })
      .from(schema.bestEffort)
      .where(
        and(
          eq(schema.bestEffort.userId, userId),
          eq(schema.bestEffort.recordSet, recordSet),
          eq(schema.bestEffort.distanceM, distanceM),
        ),
      );
  }

  async setMedal(activityId: string, distanceM: number, medal: Medal | null, tx: DbExecutor): Promise<void> {
    await tx
      .update(schema.bestEffort)
      .set({ medal })
      .where(and(eq(schema.bestEffort.activityId, activityId), eq(schema.bestEffort.distanceM, distanceM)));
  }

  /**
   * Sets `removed_at` on the athlete's own row (kept when already removed). Returns its family,
   * undefined when the athlete has no such row.
   */
  async markRemoved(
    userId: string,
    activityId: string,
    distanceM: number,
    tx: DbExecutor,
  ): Promise<RecordSet | undefined> {
    const [row] = await tx
      .update(schema.bestEffort)
      .set({ removedAt: sql`coalesce(${schema.bestEffort.removedAt}, now())`, medal: null })
      .where(
        and(
          eq(schema.bestEffort.userId, userId),
          eq(schema.bestEffort.activityId, activityId),
          eq(schema.bestEffort.distanceM, distanceM),
        ),
      )
      .returning({ recordSet: schema.bestEffort.recordSet });
    return row?.recordSet;
  }

  /** The Best efforts of an Activity not removed, shortest distance first. */
  findStanding(activityId: string): Promise<BestEffortRow[]> {
    return this.db
      .select()
      .from(schema.bestEffort)
      .where(and(eq(schema.bestEffort.activityId, activityId), isNull(schema.bestEffort.removedAt)))
      .orderBy(asc(schema.bestEffort.distanceM));
  }
}
