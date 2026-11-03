import { Inject, Injectable } from "@nestjs/common";
import { and, asc, count, desc, eq, inArray, sql, type AnyColumn } from "drizzle-orm";
import type { Visibility } from "@repo/contracts";
import { schema, type Database } from "@repo/db";
import { DATABASE, type DbExecutor } from "../../infrastructure/index.js";
import type { ActivityMediaRecord } from "../domain/activity-media.js";
import type { GalleryCursor } from "../domain/gallery-cursor.js";
import { mediaPositions } from "../domain/media-order.js";

/** A Gallery row: the Media, its keyset position and its Activity. */
export interface GalleryRow extends ActivityMediaRecord {
  position: number;
  /** `created_at` in UTC with its microseconds. */
  createdAtMicros: string;
  activityTitle: string;
  activityStartedAt: Date;
  /** The Activity's `started_at` in UTC with its microseconds. */
  activityStartedAtMicros: string;
}

/** A timestamp in UTC to the microsecond, `YYYY-MM-DDTHH:MM:SS.ffffffZ` (a JS `Date` keeps milliseconds). */
function micros(column: AnyColumn) {
  return sql<string>`to_char(${column} at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')`;
}

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

  /**
   * One page of an athlete's Gallery (ADR-037 §9): the Media of their processed Activities with
   * one of `visibilities`, newest Activity first (`started_at desc, id desc`, as their Activities
   * tab), then the read order within it. Reads `limit` rows; timestamps come back with their
   * microseconds for the next cursor.
   */
  findGalleryPage(params: {
    userId: string;
    visibilities: readonly Visibility[];
    after: GalleryCursor | undefined;
    limit: number;
  }): Promise<GalleryRow[]> {
    const { userId, visibilities, after, limit } = params;
    const media = schema.activityMedia;
    const activity = schema.activity;
    const startedAtMicros = micros(activity.startedAt);
    const createdAtMicros = micros(media.createdAt);
    // Activities descend and Media ascend: no single row comparison covers both.
    const following = after
      ? sql`((${activity.startedAt}, ${activity.id}) < (${after.activityStartedAt}::timestamptz, ${after.activityId}::uuid)
          or ((${activity.startedAt}, ${activity.id}) = (${after.activityStartedAt}::timestamptz, ${after.activityId}::uuid)
            and (${media.position}, ${media.createdAt}, ${media.id}) > (${after.position}, ${after.createdAt}::timestamptz, ${after.mediaId}::uuid)))`
      : undefined;
    return this.db
      .select({
        ...RECORD,
        position: media.position,
        createdAtMicros,
        activityTitle: activity.title,
        activityStartedAt: activity.startedAt,
        activityStartedAtMicros: startedAtMicros,
      })
      .from(media)
      .innerJoin(activity, eq(activity.id, media.activityId))
      .where(
        and(
          eq(activity.userId, userId),
          eq(activity.processingStatus, "processed"),
          inArray(activity.visibility, [...visibilities]),
          following,
        ),
      )
      .orderBy(desc(activity.startedAt), desc(activity.id), asc(media.position), asc(media.createdAt), asc(media.id))
      .limit(limit);
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

  /**
   * Applies a wanted order (ADR-037 §8, `mediaPositions`) to the Activity's Media, rows locked
   * until the end of `tx`. Writes only the positions that move; `true` when the read order
   * `(position, created_at)` changed.
   */
  async reorder(activityId: string, wantedOrder: readonly string[], tx: DbExecutor): Promise<boolean> {
    const table = schema.activityMedia;
    const rows = await tx
      .select({ id: table.id, position: table.position })
      .from(table)
      .where(eq(table.activityId, activityId))
      .orderBy(asc(table.position), asc(table.createdAt), asc(table.id))
      .for("update");
    const currentIds = rows.map((row) => row.id);
    const positions = mediaPositions(currentIds, wantedOrder);
    for (const row of rows) {
      const position = positions.get(row.id);
      if (position !== undefined && position !== row.position) {
        await tx.update(table).set({ position }).where(eq(table.id, row.id));
      }
    }
    const reordered = [...currentIds].sort((a, b) => (positions.get(a) ?? 0) - (positions.get(b) ?? 0));
    return reordered.some((id, index) => id !== currentIds[index]);
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
