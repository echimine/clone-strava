import { Inject, Injectable } from "@nestjs/common";
import { and, eq, inArray, sql } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE, type DbExecutor } from "../../infrastructure/index.js";
import type { EffortSyncPlan, StoredEffort } from "../domain/effort-sync.js";
import type { Medal, MedalEffort } from "../domain/segment-medals.js";

/** Reads and writes on `segments.segment_effort` only (ADR-021 §6). */
@Injectable()
export class SegmentEffortRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  /**
   * Serializes, until the end of the transaction, every write on one athlete's Efforts and Medals
   * (ADR-039 §8): a replay always reads the Efforts other jobs committed.
   */
  async lockAthlete(userId: string, tx: DbExecutor): Promise<void> {
    await tx.execute(sql`select pg_advisory_xact_lock(hashtextextended(${`segment-efforts:${userId}`}, 0))`);
  }

  /** An Activity's Efforts, on one Segment only when `segmentId` is given. */
  findByActivity(activityId: string, segmentId: string | undefined, tx: DbExecutor): Promise<StoredEffort[]> {
    const effort = schema.segmentEffort;
    return tx
      .select({
        id: effort.id,
        segmentId: effort.segmentId,
        startIndex: effort.startIndex,
        startedAt: effort.startedAt,
        elapsedTimeS: effort.elapsedTimeS,
        status: effort.status,
      })
      .from(effort)
      .where(and(eq(effort.activityId, activityId), segmentId ? eq(effort.segmentId, segmentId) : undefined));
  }

  /** Applies a sync plan for one Activity of one athlete (ADR-039 §6). */
  async apply(
    activity: { activityId: string; userId: string },
    plan: EffortSyncPlan,
    tx: DbExecutor,
  ): Promise<void> {
    const effort = schema.segmentEffort;
    if (plan.deletes.length > 0) {
      await tx.delete(effort).where(inArray(effort.id, plan.deletes));
    }
    for (const update of plan.updates) {
      await tx
        .update(effort)
        .set({
          endIndex: update.endIndex,
          startedAt: new Date(update.startedAtMs),
          elapsedTimeS: update.elapsedTimeS,
          minDistanceToActivityStartM: update.minDistanceToActivityStartM,
          minDistanceToActivityEndM: update.minDistanceToActivityEndM,
        })
        .where(eq(effort.id, update.id));
    }
    if (plan.inserts.length > 0) {
      await tx.insert(effort).values(
        plan.inserts.map((found) => ({
          activityId: activity.activityId,
          userId: activity.userId,
          segmentId: found.segmentId,
          startIndex: found.startIndex,
          endIndex: found.endIndex,
          startedAt: new Date(found.startedAtMs),
          elapsedTimeS: found.elapsedTimeS,
          minDistanceToActivityStartM: found.minDistanceToActivityStartM,
          minDistanceToActivityEndM: found.minDistanceToActivityEndM,
          status: found.status,
        })),
      );
    }
  }

  /** An athlete's Efforts, on these Segments only when given, for the Medal replay. */
  async findForMedals(
    userId: string,
    segmentIds: string[] | undefined,
    tx: DbExecutor,
  ): Promise<Array<MedalEffort & { segmentId: string; medal: Medal | null }>> {
    if (segmentIds?.length === 0) {
      return [];
    }
    const effort = schema.segmentEffort;
    return tx
      .select({
        id: effort.id,
        segmentId: effort.segmentId,
        startedAt: effort.startedAt,
        elapsedTimeS: effort.elapsedTimeS,
        status: effort.status,
        medal: effort.medal,
      })
      .from(effort)
      .where(and(eq(effort.userId, userId), segmentIds ? inArray(effort.segmentId, segmentIds) : undefined));
  }

  async setMedal(effortId: string, medal: Medal | null, tx: DbExecutor): Promise<void> {
    await tx.update(schema.segmentEffort).set({ medal }).where(eq(schema.segmentEffort.id, effortId));
  }
}
