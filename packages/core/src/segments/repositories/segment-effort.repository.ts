import { Inject, Injectable, NotImplementedException } from "@nestjs/common";
import { type Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";

/** Reads and writes on `segments.segment_effort` only (ADR-021 §6). */
@Injectable()
export class SegmentEffortRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  /** Upsert (ADR-019 §8): one effort per activity/segment, replayable. */
  async upsert(_values: {
    activityId: string;
    segmentId: string;
    userId: string;
    elapsedTimeS: number;
    startedAt: Date;
  }): Promise<void> {
    throw new NotImplementedException();
  }

  /** Recomputes `rank` for every effort of a segment (ADR-019 §8). */
  async recomputeLeaderboard(_segmentId: string): Promise<void> {
    throw new NotImplementedException();
  }
}
