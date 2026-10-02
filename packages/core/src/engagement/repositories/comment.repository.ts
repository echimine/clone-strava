import { Inject, Injectable, NotImplementedException } from "@nestjs/common";
import { and, count, inArray, isNull } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";

/** Reads and writes on `engagement.comment` only (ADR-021 §6). */
@Injectable()
export class CommentRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  /** Non-deleted comments per activity (`comment_activity_created_at_idx`). */
  async countByActivityIds(activityIds: string[]): Promise<Map<string, number>> {
    if (activityIds.length === 0) {
      return new Map();
    }
    const rows = await this.db
      .select({ activityId: schema.comment.activityId, total: count() })
      .from(schema.comment)
      .where(and(inArray(schema.comment.activityId, activityIds), isNull(schema.comment.deletedAt)))
      .groupBy(schema.comment.activityId);
    return new Map(rows.map((row) => [row.activityId, row.total]));
  }

  async add(_userId: string, _activityId: string, _body: string): Promise<void> {
    throw new NotImplementedException();
  }
}
