import { Inject, Injectable } from "@nestjs/common";
import { and, asc, eq, gt, inArray, isNull, lt, or, sql } from "drizzle-orm";
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
   * One page of every processed Activity of these sports, by id after `afterId` (ADR-039 §7: the
   * per-Activity replay after a Nervo import).
   */
  pageProcessed(
    sportTypeCodes: readonly string[],
    afterId: string | null,
    limit: number,
  ): Promise<Array<{ activityId: string; userId: string }>> {
    const view = schema.leaderboardActivity;
    return this.db
      .select({ activityId: view.id, userId: view.userId })
      .from(view)
      .where(
        and(
          inArray(view.sportTypeCode, [...sportTypeCodes]),
          afterId === null ? undefined : gt(view.id, afterId),
        ),
      )
      .orderBy(asc(view.id))
      .limit(limit);
  }

  /**
   * Writes the matching version of every processed Activity of a sport outside these ones never
   * matched or matched with an older version (ADR-039 §6, §13): such a sport has no Segment, so no
   * job is needed. Returns how many rows were written.
   */
  async markOtherSportsMatched(sportTypeCodes: readonly string[], version: number): Promise<number> {
    // `'{a,b}'::text[]`: an interpolated array would spread into a tuple.
    const sports = `{${sportTypeCodes.join(",")}}`;
    const written = await this.db.execute(sql`
      insert into segments.activity_matching (activity_id, version, matched_at)
      select published.id, ${version}::int, now()
        from activities.leaderboard_activity published
        left join segments.activity_matching matching on matching.activity_id = published.id
       where published.sport_type_code <> all(${sports}::text[])
         and (matching.activity_id is null or matching.version < ${version}::int)
      on conflict (activity_id) do update set version = excluded.version, matched_at = excluded.matched_at
      returning activity_id`);
    return written.rows.length;
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
