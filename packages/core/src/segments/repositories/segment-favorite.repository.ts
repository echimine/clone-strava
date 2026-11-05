import { Inject, Injectable } from "@nestjs/common";
import { and, eq } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";

/**
 * Reads and writes on `segments.segment_favorite` (ADR-039 §5). Minimal version written by #250
 * for the Map's star; #249 owns it and its version wins at the merge.
 */
@Injectable()
export class SegmentFavoriteRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  /** Stars it, idempotent; `false` when the Segment does not exist. */
  async add(userId: string, segmentId: string): Promise<boolean> {
    const [segment] = await this.db
      .select({ id: schema.segment.id })
      .from(schema.segment)
      .where(eq(schema.segment.id, segmentId));
    if (!segment) {
      return false;
    }
    await this.db.insert(schema.segmentFavorite).values({ userId, segmentId }).onConflictDoNothing();
    return true;
  }

  /** Unstars it, idempotent; `false` when the Segment does not exist. */
  async remove(userId: string, segmentId: string): Promise<boolean> {
    const [segment] = await this.db
      .select({ id: schema.segment.id })
      .from(schema.segment)
      .where(eq(schema.segment.id, segmentId));
    if (!segment) {
      return false;
    }
    await this.db
      .delete(schema.segmentFavorite)
      .where(and(eq(schema.segmentFavorite.userId, userId), eq(schema.segmentFavorite.segmentId, segmentId)));
    return true;
  }
}
