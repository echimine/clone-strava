import { Inject, Injectable } from "@nestjs/common";
import { and, asc, count, desc, eq, inArray, lte, sql } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE, notInIds } from "../../infrastructure/index.js";
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
   * The user ids of the last `perActivity` kudos of each activity, most recent first
   * (ADR-036 §5), in one query: `row_number()` per activity over
   * `kudos_activity_created_at_idx`. Activities without kudos are absent.
   */
  async findRecentGiverIds(
    activityIds: string[],
    perActivity: number,
    excludedUserIds: readonly string[] = [],
  ): Promise<Map<string, string[]>> {
    if (activityIds.length === 0 || perActivity <= 0) {
      return new Map();
    }
    const { activityId, createdAt, userId } = schema.kudos;
    const ranked = this.db
      .select({
        activityId,
        userId,
        rank: sql<number>`row_number() over (partition by ${activityId} order by ${createdAt} desc, ${userId} desc)`.as(
          "rank",
        ),
      })
      .from(schema.kudos)
      .where(and(inArray(activityId, activityIds), notInIds(userId, excludedUserIds)))
      .as("ranked");
    const rows = await this.db
      .select({ activityId: ranked.activityId, userId: ranked.userId })
      .from(ranked)
      .where(lte(ranked.rank, perActivity))
      .orderBy(asc(ranked.activityId), asc(ranked.rank));

    const giverIds = new Map<string, string[]>();
    for (const row of rows) {
      giverIds.set(row.activityId, [...(giverIds.get(row.activityId) ?? []), row.userId]);
    }
    return giverIds;
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
    excludedUserIds: readonly string[] = [],
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
      .where(and(eq(schema.kudos.activityId, activityId), notInIds(userId, excludedUserIds), older))
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
