import { Inject, Injectable } from "@nestjs/common";
import { inArray } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";

/**
 * Which bucket folders still have their row (ADR-037 §11), read-only and in batch, for the
 * `bucket-sweep`: `activity`, `activity_media` and `activity_import`, all owned by `activities`.
 */
@Injectable()
export class BucketReferencesRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  /** The owner of each existing Activity among `ids`. */
  activityOwners(ids: readonly string[]): Promise<Array<{ id: string; userId: string }>> {
    const t = schema.activity;
    return ids.length === 0
      ? Promise.resolve([])
      : this.db.select({ id: t.id, userId: t.userId }).from(t).where(inArray(t.id, [...ids]));
  }

  /** The Activity of each existing Media among `ids`. */
  mediaActivities(ids: readonly string[]): Promise<Array<{ id: string; activityId: string }>> {
    const t = schema.activityMedia;
    return ids.length === 0
      ? Promise.resolve([])
      : this.db.select({ id: t.id, activityId: t.activityId }).from(t).where(inArray(t.id, [...ids]));
  }

  /** The owner of each existing import among `ids`. */
  importOwners(ids: readonly string[]): Promise<Array<{ id: string; userId: string }>> {
    const t = schema.activityImport;
    return ids.length === 0
      ? Promise.resolve([])
      : this.db.select({ id: t.id, userId: t.userId }).from(t).where(inArray(t.id, [...ids]));
  }
}
