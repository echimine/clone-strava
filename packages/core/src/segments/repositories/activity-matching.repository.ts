import { Inject, Injectable } from "@nestjs/common";
import { and, asc, eq, inArray, isNull, lt, or, sql } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE, type DbExecutor } from "../../infrastructure/index.js";

/**
 * Reads and writes on `segments.activity_matching`, joined read-only with the published view
 * `activities.leaderboard_activity` (ADR-021 §7 amended, ADR-039 §2).
 */
@Injectable()
export class ActivityMatchingRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  async upsert(activityId: string, version: number, tx: DbExecutor): Promise<void> {
    await tx
      .insert(schema.activityMatching)
      .values({ activityId, version, matchedAt: sql`now()` })
      .onConflictDoUpdate({
        target: schema.activityMatching.activityId,
        set: { version, matchedAt: sql`now()` },
      });
  }

  /**
   * Processed Activities of these sports never matched, or matched with an older version
   * (ADR-039 §13), oldest id first.
   */
  findLagging(
    sportTypeCodes: readonly string[],
    version: number,
    limit: number,
  ): Promise<Array<{ activityId: string; userId: string }>> {
    const view = schema.leaderboardActivity;
    const matching = schema.activityMatching;
    return this.db
      .select({ activityId: view.id, userId: view.userId })
      .from(view)
      .leftJoin(matching, eq(matching.activityId, view.id))
      .where(
        and(
          inArray(view.sportTypeCode, [...sportTypeCodes]),
          or(isNull(matching.activityId), lt(matching.version, version)),
        ),
      )
      .orderBy(asc(view.id))
      .limit(limit);
  }
}
