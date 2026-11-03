import { Inject, Injectable } from "@nestjs/common";
import { asc, eq, inArray } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE, type DbExecutor } from "../../infrastructure/index.js";
import type { ActivityMediaRecord } from "../domain/activity-media.js";
import { mediaPositions } from "../domain/media-order.js";

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
      .select({
        id: table.id,
        activityId: table.activityId,
        kind: table.kind,
        width: table.width,
        height: table.height,
        durationMs: table.durationMs,
        folderKey: table.s3Key,
      })
      .from(table)
      .where(inArray(table.activityId, activityIds))
      .orderBy(asc(table.activityId), asc(table.position), asc(table.createdAt), asc(table.id));
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
