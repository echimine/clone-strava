import { Inject, Injectable } from "@nestjs/common";
import { and, count, desc, eq, inArray, isNull, lt, or } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE, NO_EXCLUSIONS, notInIds, type ViewerExclusions } from "../../infrastructure/index.js";
import type { CommentCursor } from "../domain/comment-cursor.js";
import type { CommentRecord } from "../domain/comment-record.js";

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

  /** Any comment with this id, deleted or not, whatever its Activity. */
  findById(id: string): Promise<CommentRecord | undefined> {
    return this.db.query.comment.findFirst({ where: eq(schema.comment.id, id) });
  }

  /**
   * Non-deleted comments of an activity, newest first, strictly older than
   * `before` when given (keyset on `created_at desc, id desc`), without the
   * hidden authors and reported comments of `exclusions` (ADR-038 §7).
   */
  findPage(
    activityId: string,
    before: CommentCursor | undefined,
    limit: number,
    exclusions: ViewerExclusions = NO_EXCLUSIONS,
  ): Promise<CommentRecord[]> {
    const older = before
      ? or(
          lt(schema.comment.createdAt, before.createdAt),
          and(eq(schema.comment.createdAt, before.createdAt), lt(schema.comment.id, before.id)),
        )
      : undefined;
    return this.db
      .select()
      .from(schema.comment)
      .where(
        and(
          eq(schema.comment.activityId, activityId),
          isNull(schema.comment.deletedAt),
          notInIds(schema.comment.userId, exclusions.hiddenAthleteIds),
          notInIds(schema.comment.id, exclusions.reportedCommentIds),
          older,
        ),
      )
      .orderBy(desc(schema.comment.createdAt), desc(schema.comment.id))
      .limit(limit);
  }

  /**
   * Inserts the comment unless its id is taken. `createdAt` comes from the
   * app (millisecond precision) so the opaque cursor round-trips exactly.
   */
  async insertIfAbsent(values: {
    id: string;
    activityId: string;
    userId: string;
    body: string;
    createdAt: Date;
  }): Promise<boolean> {
    const rows = await this.db
      .insert(schema.comment)
      .values(values)
      .onConflictDoNothing()
      .returning({ id: schema.comment.id });
    return rows.length > 0;
  }

  /** Replaces the body of a non-deleted comment; `undefined` when it is gone. */
  async updateBody(id: string, body: string, updatedAt: Date): Promise<CommentRecord | undefined> {
    const [row] = await this.db
      .update(schema.comment)
      .set({ body, updatedAt })
      .where(and(eq(schema.comment.id, id), isNull(schema.comment.deletedAt)))
      .returning();
    return row;
  }

  /** Soft delete (ADR-017); `false` when the comment was already deleted. */
  async softDelete(id: string, deletedAt: Date): Promise<boolean> {
    const rows = await this.db
      .update(schema.comment)
      .set({ deletedAt })
      .where(and(eq(schema.comment.id, id), isNull(schema.comment.deletedAt)))
      .returning({ id: schema.comment.id });
    return rows.length > 0;
  }

  /** The ids among `ids` of comments not deleted (Journal links, ADR-038 §3). */
  async findExistingIds(ids: string[]): Promise<Set<string>> {
    if (ids.length === 0) {
      return new Set();
    }
    const rows = await this.db
      .select({ id: schema.comment.id })
      .from(schema.comment)
      .where(and(inArray(schema.comment.id, ids), isNull(schema.comment.deletedAt)));
    return new Set(rows.map((row) => row.id));
  }
}
