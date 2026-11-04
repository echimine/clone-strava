import { Inject, Injectable } from "@nestjs/common";
import { and, count, eq } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE, notByUsers, withinRange, type InstantRange } from "../../infrastructure/index.js";

/** Backoffice dashboard counts (ADR-038 §15) over `follow`. */
@Injectable()
export class FollowAdminStatsRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  /**
   * Follows in place (`accepted`) whose request was made in `range`, by their follower; pending
   * requests are not Follows yet.
   */
  async countFollowsCreated(range: InstantRange, excludedUserIds: readonly string[]): Promise<number> {
    const [row] = await this.db
      .select({ total: count() })
      .from(schema.follow)
      .where(
        and(
          eq(schema.follow.status, "accepted"),
          withinRange(schema.follow.createdAt, range),
          notByUsers(schema.follow.followerId, excludedUserIds),
        ),
      );
    return row?.total ?? 0;
  }
}
