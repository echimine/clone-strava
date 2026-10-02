import { Inject, Injectable } from "@nestjs/common";
import { schema, type Database } from "@repo/db";
import { DATABASE, type DbExecutor } from "../../infrastructure/index.js";

/** Reads and writes on `activities.activity_stats` only (ADR-021 §6). */
@Injectable()
export class ActivityStatsRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  /** Upsert (ADR-019 §5 step 7): the `process-activity` job is replayable without duplicates. */
  async upsert(
    values: typeof schema.activityStats.$inferInsert,
    executor: DbExecutor = this.db,
  ): Promise<void> {
    const { activityId: _activityId, ...updates } = values;
    await executor
      .insert(schema.activityStats)
      .values(values)
      .onConflictDoUpdate({ target: schema.activityStats.activityId, set: updates });
  }
}
