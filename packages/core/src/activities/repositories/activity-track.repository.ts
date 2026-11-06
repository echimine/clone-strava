import { Inject, Injectable } from "@nestjs/common";
import { eq, inArray } from "drizzle-orm";
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
        routeTrimmed: schema.activityTrack.routeTrimmed,
      })
      .from(schema.activityTrack)
      .where(inArray(schema.activityTrack.activityId, ids));
  }

  /** Whether the Activity has a stored trace: none for a manual Activity nor a pool swim. */
  async exists(activityId: string): Promise<boolean> {
    const [row] = await this.db
      .select({ activityId: schema.activityTrack.activityId })
      .from(schema.activityTrack)
      .where(eq(schema.activityTrack.activityId, activityId));
    return row !== undefined;
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
