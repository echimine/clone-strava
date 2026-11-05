import { Inject, Injectable } from "@nestjs/common";
import type { Database } from "@repo/db";
import { DATABASE, type DbExecutor } from "../../infrastructure/index.js";
import { planEffortSync, type FoundEffort } from "../domain/effort-sync.js";
import { replaySegmentMedals } from "../domain/segment-medals.js";
import { SegmentEffortRepository } from "../repositories/segment-effort.repository.js";

/** The Activity whose Efforts are recorded. */
export interface MatchedActivity {
  activityId: string;
  userId: string;
  sportTypeCode: string;
  visibility: string;
}

/**
 * Writes what the matching found and replays the Medals it touches (ADR-039 §6, §8), shared by
 * `match-segments`, the retro-matching and `replay-segment-medals`. Each athlete's writes are
 * serialized by a transaction-scoped lock, so a replay never misses a concurrent job's Efforts.
 */
@Injectable()
export class EffortRecorder {
  constructor(
    @Inject(DATABASE) private readonly db: Database,
    private readonly efforts: SegmentEffortRepository,
  ) {}

  /**
   * Replaces the Activity's Efforts, on every Segment or on `onlySegmentId`, by `found`, then
   * replays the Medals of every Segment touched. `alsoInTransaction` writes more in the same
   * transaction (the matching version).
   */
  async record(
    activity: MatchedActivity,
    found: FoundEffort[],
    options: { onlySegmentId?: string; alsoInTransaction?: (tx: DbExecutor) => Promise<void> } = {},
  ): Promise<void> {
    await this.db.transaction(async (tx) => {
      await this.efforts.lockAthlete(activity.userId, tx);
      const previous = await this.efforts.findByActivity(activity.activityId, options.onlySegmentId, tx);
      await this.efforts.apply(activity, planEffortSync(previous, found, activity), tx);
      const touched = new Set([...previous, ...found].map((effort) => effort.segmentId));
      await this.replay(activity.userId, [...touched], tx);
      await options.alsoInTransaction?.(tx);
    });
  }

  /** `replay-segment-medals`: every Segment Medal of the athlete (ADR-039 §8, §13). */
  async replayAll(userId: string): Promise<void> {
    await this.db.transaction(async (tx) => {
      await this.efforts.lockAthlete(userId, tx);
      await this.replay(userId, undefined, tx);
    });
  }

  private async replay(userId: string, segmentIds: string[] | undefined, tx: DbExecutor): Promise<void> {
    const efforts = await this.efforts.findForMedals(userId, segmentIds, tx);
    const bySegment = new Map<string, typeof efforts>();
    for (const effort of efforts) {
      bySegment.set(effort.segmentId, [...(bySegment.get(effort.segmentId) ?? []), effort]);
    }
    for (const segmentEfforts of bySegment.values()) {
      const medals = replaySegmentMedals(segmentEfforts);
      for (const effort of segmentEfforts) {
        const medal = medals.get(effort.id) ?? null;
        if (medal !== effort.medal) {
          await this.efforts.setMedal(effort.id, medal, tx);
        }
      }
    }
  }
}
