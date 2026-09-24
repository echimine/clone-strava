import { Inject, Injectable, NotImplementedException } from "@nestjs/common";
import { schema, type Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";

/** Reads and writes on `activities.activity_stats` only (ADR-021 §6). */
@Injectable()
export class ActivityStatsRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  /** Upsert (ADR-019 §5 step 7): the `process-activity` job is replayable without duplicates. */
  async upsert(_values: typeof schema.activityStats.$inferInsert): Promise<void> {
    throw new NotImplementedException();
  }
}
