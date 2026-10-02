import { Inject, Injectable } from "@nestjs/common";
import { inArray } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE, type DbExecutor } from "../../infrastructure/index.js";

/** Reads and writes on `activities.activity_stats` only (ADR-021 §6). */
@Injectable()
export class ActivityStatsRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  findByActivityIds(ids: string[]) {
    if (ids.length === 0) {
      return Promise.resolve([]);
    }
    return this.db.select().from(schema.activityStats).where(inArray(schema.activityStats.activityId, ids));
  }

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
