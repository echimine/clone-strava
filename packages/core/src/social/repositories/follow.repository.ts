import { Inject, Injectable } from "@nestjs/common";
import { and, count, desc, eq, inArray, sql } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE, type DbExecutor } from "../../infrastructure/index.js";
import type { FollowCursor } from "../domain/follow-cursor.js";

type FollowStatus = "pending" | "accepted";

/** Reads and writes on `social.follow` only (ADR-021 §6). */
@Injectable()
export class FollowRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  findFolloweeIds(followerId: string) {
    return this.db.query.follow.findMany({
      where: and(
        eq(schema.follow.followerId, followerId),
        eq(schema.follow.status, "accepted"),
      ),
      columns: { followeeId: true },
    });
  }

  findOne(followerId: string, followeeId: string) {
    return this.db.query.follow.findFirst({
      where: and(
        eq(schema.follow.followerId, followerId),
        eq(schema.follow.followeeId, followeeId),
      ),
    });
  }

  /** Idempotent: an existing row (pending or accepted) is left as is. */
  async insertIfAbsent(followerId: string, followeeId: string, status: FollowStatus): Promise<void> {
    await this.db.insert(schema.follow).values({ followerId, followeeId, status }).onConflictDoNothing();
  }

  /** Accepted followers per athlete; athletes without any are absent. */
  async countFollowers(athleteIds: string[]): Promise<Map<string, number>> {
    if (athleteIds.length === 0) {
      return new Map();
    }
    const rows = await this.db
      .select({ athleteId: schema.follow.followeeId, total: count() })
      .from(schema.follow)
      .where(and(inArray(schema.follow.followeeId, athleteIds), eq(schema.follow.status, "accepted")))
      .groupBy(schema.follow.followeeId);
    return new Map(rows.map((row) => [row.athleteId, row.total]));
  }

  /** Accepted followees per athlete; athletes following nobody are absent. */
  async countFollowing(athleteIds: string[]): Promise<Map<string, number>> {
    if (athleteIds.length === 0) {
      return new Map();
    }
    const rows = await this.db
      .select({ athleteId: schema.follow.followerId, total: count() })
      .from(schema.follow)
      .where(and(inArray(schema.follow.followerId, athleteIds), eq(schema.follow.status, "accepted")))
      .groupBy(schema.follow.followerId);
    return new Map(rows.map((row) => [row.athleteId, row.total]));
  }

  /**
   * Up to `limit` accepted followers of `athleteId` whom `viewerId` follows (accepted), most
   * recent follow of the athlete first (ADR-036 §3 "followersYouKnow").
   */
  async findFollowersFollowedBy(athleteId: string, viewerId: string, limit: number): Promise<string[]> {
    const rows = await this.db
      .select({ followerId: schema.follow.followerId })
      .from(schema.follow)
      .where(
        and(
          eq(schema.follow.followeeId, athleteId),
          eq(schema.follow.status, "accepted"),
          sql`exists (
            select 1 from ${schema.follow} as known
            where known.follower_id = ${viewerId}::uuid
              and known.followee_id = ${schema.follow.followerId}
              and known.status = 'accepted'
          )`,
        ),
      )
      .orderBy(desc(schema.follow.createdAt), desc(schema.follow.followerId))
      .limit(limit);
    return rows.map((row) => row.followerId);
  }

  /** Incoming `pending` follows of `followeeId`. */
  async countPending(followeeId: string): Promise<number> {
    const [row] = await this.db
      .select({ total: count() })
      .from(schema.follow)
      .where(and(eq(schema.follow.followeeId, followeeId), eq(schema.follow.status, "pending")));
    return row?.total ?? 0;
  }

  /**
   * One keyset page of a follow list (ADR-036 §1): the `followers` of
   * `athleteId` (rows where they are the followee) or whom they are
   * `following`, with `status`, most recent first and strictly after
   * `after`. `athleteId` of a row is the listed athlete; `at` is
   * `created_at` with its microseconds, for the next cursor.
   */
  findPage(
    athleteId: string,
    side: "followers" | "following",
    status: FollowStatus,
    after: FollowCursor | undefined,
    limit: number,
  ): Promise<{ athleteId: string; createdAt: Date; at: string }[]> {
    const { createdAt, followerId, followeeId } = schema.follow;
    const [owner, listed] = side === "followers" ? [followeeId, followerId] : [followerId, followeeId];
    const older = after
      ? sql`(${createdAt}, ${listed}) < (${after.at}::timestamptz, ${after.athleteId}::uuid)`
      : undefined;
    return this.db
      .select({
        athleteId: listed,
        createdAt,
        at: sql<string>`to_char(${createdAt} at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')`,
      })
      .from(schema.follow)
      .where(and(eq(owner, athleteId), eq(schema.follow.status, status), older))
      .orderBy(desc(createdAt), desc(listed))
      .limit(limit);
  }

  /** `pending` → `accepted`. Returns whether a pending request existed. */
  async accept(followerId: string, followeeId: string): Promise<boolean> {
    const updated = await this.db
      .update(schema.follow)
      .set({ status: "accepted" })
      .where(this.row(followerId, followeeId, "pending"))
      .returning({ followerId: schema.follow.followerId });
    return updated.length > 0;
  }

  /** Accepts every pending request to `followeeId` (approval turned off, ADR-036 §1). */
  async acceptAllPending(followeeId: string, executor: DbExecutor = this.db): Promise<void> {
    await executor
      .update(schema.follow)
      .set({ status: "accepted" })
      .where(and(eq(schema.follow.followeeId, followeeId), eq(schema.follow.status, "pending")));
  }

  /** Idempotent: deletes the row, restricted to `status` when given. */
  async delete(followerId: string, followeeId: string, status?: FollowStatus): Promise<void> {
    await this.db.delete(schema.follow).where(this.row(followerId, followeeId, status));
  }

  private row(followerId: string, followeeId: string, status?: FollowStatus) {
    return and(
      eq(schema.follow.followerId, followerId),
      eq(schema.follow.followeeId, followeeId),
      status === undefined ? undefined : eq(schema.follow.status, status),
    );
  }

  /** The viewer's follow rows towards `athleteIds` (any status). */
  async findStatuses(viewerId: string, athleteIds: string[]): Promise<{ athleteId: string; status: FollowStatus }[]> {
    if (athleteIds.length === 0) {
      return [];
    }
    return this.db
      .select({ athleteId: schema.follow.followeeId, status: schema.follow.status })
      .from(schema.follow)
      .where(and(eq(schema.follow.followerId, viewerId), inArray(schema.follow.followeeId, athleteIds)));
  }
}
