import { Inject, Injectable } from "@nestjs/common";
import { asc, inArray } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";
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
}
