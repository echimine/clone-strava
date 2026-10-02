import { Inject, Injectable } from "@nestjs/common";
import { inArray } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE, type DbExecutor } from "../../infrastructure/index.js";

/** Reads and writes on `activities.activity_track` only (ADR-021 §6). */
@Injectable()
export class ActivityTrackRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  /** Feed card fields only (ADR-029): no geometry is read. */
  findFeedFieldsByActivityIds(ids: string[]) {
    if (ids.length === 0) {
      return Promise.resolve([]);
    }
    return this.db
      .select({
        activityId: schema.activityTrack.activityId,
        mapPolyline: schema.activityTrack.mapPolyline,
        locationName: schema.activityTrack.locationName,
      })
      .from(schema.activityTrack)
      .where(inArray(schema.activityTrack.activityId, ids));
  }

  /** Upsert (ADR-019 §5 step 7), route already passed through the privacy zone. */
  async upsert(
    values: typeof schema.activityTrack.$inferInsert,
    executor: DbExecutor = this.db,
  ): Promise<void> {
    const { activityId: _activityId, ...updates } = values;
    await executor
      .insert(schema.activityTrack)
      .values(values)
      .onConflictDoUpdate({ target: schema.activityTrack.activityId, set: updates });
  }
}
