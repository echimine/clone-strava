import { Inject, Injectable } from "@nestjs/common";
import { and, count, desc, eq, inArray, sql } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";
import type { KudosCursor } from "../domain/kudos-cursor.js";

/** Reads and writes on `engagement.kudos` only (ADR-021 §6). */
@Injectable()
export class KudosRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  findOne(userId: string, activityId: string) {
    return this.db.query.kudos.findFirst({
      where: and(eq(schema.kudos.userId, userId), eq(schema.kudos.activityId, activityId)),
    });
  }

  async countByActivityIds(activityIds: string[]): Promise<Map<string, number>> {
    if (activityIds.length === 0) {
      return new Map();
    }
    const rows = await this.db
      .select({ activityId: schema.kudos.activityId, total: count() })
      .from(schema.kudos)
      .where(inArray(schema.kudos.activityId, activityIds))
      .groupBy(schema.kudos.activityId);
    return new Map(rows.map((row) => [row.activityId, row.total]));
  }

  /** The subset of `activityIds` the user gave kudos to. */
  async findKudoedActivityIds(userId: string, activityIds: string[]): Promise<Set<string>> {
    if (activityIds.length === 0) {
      return new Set();
    }
    const rows = await this.db
      .select({ activityId: schema.kudos.activityId })
      .from(schema.kudos)
      .where(and(eq(schema.kudos.userId, userId), inArray(schema.kudos.activityId, activityIds)));
    return new Set(rows.map((row) => row.activityId));
  }

  /**
   * An activity's kudos, most recent first, strictly after `after` when
   * given (keyset on `created_at desc, user_id desc`,
   * `kudos_activity_created_at_idx`). `at` is `created_at` with its
   * microseconds, for the next cursor.
   */
  findPage(
    activityId: string,
    after: KudosCursor | undefined,
    limit: number,
  ): Promise<{ userId: string; createdAt: Date; at: string }[]> {
    const { createdAt, userId } = schema.kudos;
    const older = after
      ? sql`(${createdAt}, ${userId}) < (${after.at}::timestamptz, ${after.userId}::uuid)`
      : undefined;
    return this.db
      .select({
        userId,
        createdAt,
        at: sql<string>`to_char(${createdAt} at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')`,
      })
      .from(schema.kudos)
      .where(and(eq(schema.kudos.activityId, activityId), older))
      .orderBy(desc(createdAt), desc(userId))
      .limit(limit);
  }

  /** Idempotent: giving kudos twice keeps one row. Returns whether a row was inserted. */
  async give(userId: string, activityId: string): Promise<boolean> {
    const inserted = await this.db
      .insert(schema.kudos)
      .values({ userId, activityId })
      .onConflictDoNothing()
      .returning({ userId: schema.kudos.userId });
    return inserted.length > 0;
  }

  /** Idempotent: removing missing kudos is a no-op. Returns whether a row was deleted. */
  async remove(userId: string, activityId: string): Promise<boolean> {
    const deleted = await this.db
      .delete(schema.kudos)
      .where(and(eq(schema.kudos.userId, userId), eq(schema.kudos.activityId, activityId)))
      .returning({ userId: schema.kudos.userId });
    return deleted.length > 0;
  }
}
