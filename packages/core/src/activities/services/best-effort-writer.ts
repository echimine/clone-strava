import { Injectable } from "@nestjs/common";
import type { DbExecutor } from "../../infrastructure/index.js";
import type { BestEffort, RecordSet } from "../domain/best-efforts.js";
import { replayMedals } from "../domain/medals.js";
import { BestEffortRepository } from "../repositories/best-effort.repository.js";

/** One (family, distance) of an athlete whose Medals must be replayed. */
export interface RecordDistance {
  recordSet: RecordSet;
  distanceM: number;
}

/** The Best efforts of an Activity as its processing computed them (ADR-039 §3). */
export interface ComputedBestEfforts {
  activityId: string;
  userId: string;
  activityStartedAt: Date;
  /** The family of the sport the values were computed for; none, no Best effort. */
  recordSet: RecordSet | null;
  efforts: BestEffort[];
}

/**
 * The writes on Best efforts (ADR-039 §3, §8), always inside the caller's transaction and under
 * the athlete's lock: store an Activity's computed times, then replay the Medals of every
 * (family, distance) of the athlete they touched, in date order, silently.
 */
@Injectable()
export class BestEffortWriter {
  constructor(private readonly bestEfforts: BestEffortRepository) {}

  /**
   * Upserts the computed times of an Activity (a removed row stays removed, its time updated)
   * and deletes its rows no longer computed, except removed ones, so a removed time never comes
   * back. Then replays the Medals of the old and new distances.
   */
  async save(computed: ComputedBestEfforts, tx: DbExecutor): Promise<void> {
    await this.bestEfforts.lockAthlete(computed.userId, tx);
    const existing = await this.bestEfforts.findByActivity(computed.activityId, tx);
    const { recordSet } = computed;
    const efforts = recordSet ? computed.efforts : [];
    const kept = new Set(efforts.map((effort) => effort.distanceM));

    await this.bestEfforts.deleteDistances(
      computed.activityId,
      existing.filter((row) => !kept.has(row.distanceM) && !row.removedAt).map((row) => row.distanceM),
      tx,
    );
    await this.bestEfforts.upsert(
      efforts.map((effort) => ({
        activityId: computed.activityId,
        userId: computed.userId,
        recordSet: recordSet!,
        distanceM: effort.distanceM,
        elapsedTimeMs: effort.elapsedTimeMs,
        startDistanceM: effort.startDistanceM,
        activityStartedAt: computed.activityStartedAt,
      })),
      tx,
    );

    await this.replay(
      computed.userId,
      [...existing, ...efforts.map((effort) => ({ recordSet: recordSet!, distanceM: effort.distanceM }))],
      tx,
    );
  }

  /**
   * Replays the athlete's Medals on each of these (family, distance), in date order (ADR-039
   * §8): only the rows whose Medal changes are written. The caller holds the athlete's lock.
   */
  async replay(userId: string, touched: RecordDistance[], tx: DbExecutor): Promise<void> {
    const unique = new Map(touched.map((pair) => [`${pair.recordSet}:${pair.distanceM}`, pair]));
    for (const { recordSet, distanceM } of unique.values()) {
      const times = await this.bestEfforts.findTimes(userId, recordSet, distanceM, tx);
      const medals = replayMedals(
        times.map((row) => ({
          id: row.activityId,
          startedAt: row.activityStartedAt,
          timeMs: row.elapsedTimeMs,
          removed: row.removedAt !== null,
        })),
      );
      for (const row of times) {
        const medal = medals.get(row.activityId) ?? null;
        if (medal !== row.medal) {
          await this.bestEfforts.setMedal(row.activityId, distanceM, medal, tx);
        }
      }
    }
  }

  /** Takes the athlete's lock, then reads the (family, distance) of an Activity's rows. */
  async lockAndReadDistances(userId: string, activityId: string, tx: DbExecutor): Promise<RecordDistance[]> {
    await this.bestEfforts.lockAthlete(userId, tx);
    const rows = await this.bestEfforts.findByActivity(activityId, tx);
    return rows.map((row) => ({ recordSet: row.recordSet, distanceM: row.distanceM }));
  }
}
