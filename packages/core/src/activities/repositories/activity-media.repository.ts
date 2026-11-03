import { Inject, Injectable } from "@nestjs/common";
import { and, asc, count, eq, inArray } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE, type DbExecutor } from "../../infrastructure/index.js";
import type { ActivityMediaRecord } from "../domain/activity-media.js";

/** Reads and writes on `activities.activity_media` only (ADR-021 §6, ADR-037 §12). */
@Injectable()
export class ActivityMediaRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  /**
   * The Media of these Activities in one query, in read order `(position, created_at)`
   * (ADR-037 §8), over `activity_media_activity_position_idx`.
   */
  async findByActivityIds(activityIds: string[]): Promise<ActivityMediaRecord[]> {
    if (activityIds.length === 0) {
      return [];
    }
    const table = schema.activityMedia;
    return this.db
      .select(RECORD)
      .from(table)
      .where(inArray(table.activityId, activityIds))
      .orderBy(asc(table.activityId), asc(table.position), asc(table.createdAt), asc(table.id));
  }

  // --- Upload API (ADR-037 §4) ---

  /** The number of confirmed Media of an Activity. */
  async countByActivity(activityId: string, executor: DbExecutor = this.db): Promise<number> {
    const [row] = await executor
      .select({ value: count() })
      .from(schema.activityMedia)
      .where(eq(schema.activityMedia.activityId, activityId));
    return row?.value ?? 0;
  }

  async findById(id: string): Promise<ActivityMediaRecord | undefined> {
    const [row] = await this.db.select(RECORD).from(schema.activityMedia).where(eq(schema.activityMedia.id, id));
    return row;
  }

  /** Idempotent on `id` (a replayed confirmation inserts nothing): the new row, `undefined` if the id exists. */
  async insertIfAbsent(
    values: Omit<typeof schema.activityMedia.$inferInsert, "takenAtPoint" | "createdAt">,
    executor: DbExecutor = this.db,
  ): Promise<ActivityMediaRecord | undefined> {
    const [row] = await executor
      .insert(schema.activityMedia)
      .values(values)
      .onConflictDoNothing({ target: schema.activityMedia.id })
      .returning(RECORD);
    return row;
  }

  /** The id of the Activity's first Media in read order (ADR-037 §8), `undefined` without any. */
  async findFirstId(activityId: string, executor: DbExecutor = this.db): Promise<string | undefined> {
    const table = schema.activityMedia;
    const [row] = await executor
      .select({ id: table.id })
      .from(table)
      .where(eq(table.activityId, activityId))
      .orderBy(asc(table.position), asc(table.createdAt), asc(table.id))
      .limit(1);
    return row?.id;
  }

  /** `false` when the Activity has no such Media. */
  async delete(activityId: string, mediaId: string, executor: DbExecutor = this.db): Promise<boolean> {
    const table = schema.activityMedia;
    const deleted = await executor
      .delete(table)
      .where(and(eq(table.id, mediaId), eq(table.activityId, activityId)))
      .returning({ id: table.id });
    return deleted.length > 0;
  }
}

const RECORD = {
  id: schema.activityMedia.id,
  activityId: schema.activityMedia.activityId,
  kind: schema.activityMedia.kind,
  width: schema.activityMedia.width,
  height: schema.activityMedia.height,
  durationMs: schema.activityMedia.durationMs,
  folderKey: schema.activityMedia.s3Key,
};
