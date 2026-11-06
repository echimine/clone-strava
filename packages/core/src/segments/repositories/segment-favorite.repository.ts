import { Inject, Injectable } from "@nestjs/common";
import { and, asc, desc, eq, sql } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";
import type { ClimbCategory } from "../domain/climb-category.js";
import type { FavoriteCursor } from "../domain/favorite-cursor.js";

const f = schema.segmentFavorite;
const s = schema.segment;

/** One row of Plus › « Segments ». */
export interface FavoriteRow {
  id: string;
  sportTypeCode: string;
  name: string;
  verifiedAt: Date | null;
  distanceM: number | null;
  avgGrade: number | null;
  climbCategory: ClimbCategory | null;
  myBestTimeS: number | null;
  cursorStarredAt: string;
}

/** Reads and writes on `segments.segment_favorite` (ADR-021 §6, ADR-039 §5). */
@Injectable()
export class SegmentFavoriteRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  async segmentExists(segmentId: string): Promise<boolean> {
    const [row] = await this.db.select({ id: s.id }).from(s).where(eq(s.id, segmentId));
    return row !== undefined;
  }

  /** Idempotent: starring twice keeps the first date. */
  async add(userId: string, segmentId: string): Promise<void> {
    await this.db.insert(f).values({ userId, segmentId }).onConflictDoNothing();
  }

  async remove(userId: string, segmentId: string): Promise<void> {
    await this.db.delete(f).where(and(eq(f.userId, userId), eq(f.segmentId, segmentId)));
  }

  /**
   * The athlete's starred Segments, most recently starred first, `limit + 1` rows; with their
   * fastest Effort that is not rejected (suspicious ones count, as for Medals, ADR-039 §8).
   */
  findPage(params: { userId: string; after?: FavoriteCursor; limit: number }): Promise<FavoriteRow[]> {
    const { userId, after, limit } = params;
    const e = schema.segmentEffort;
    const myBestTimeS = sql<number | null>`(
      select min(${e.elapsedTimeS}) from ${e}
      where ${e.segmentId} = ${s.id} and ${e.userId} = ${userId} and ${e.status} <> 'rejected'
    )`;
    return this.db
      .select({
        id: s.id,
        sportTypeCode: s.sportTypeCode,
        name: s.name,
        verifiedAt: s.verifiedAt,
        distanceM: s.distanceM,
        avgGrade: s.avgGrade,
        climbCategory: s.climbCategory,
        myBestTimeS: myBestTimeS.mapWith(Number),
        cursorStarredAt: sql<string>`to_char(${f.createdAt} at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')`,
      })
      .from(f)
      .innerJoin(s, eq(s.id, f.segmentId))
      .where(
        and(
          eq(f.userId, userId),
          after
            ? sql`(${f.createdAt} < ${after.starredAt}::timestamptz or (${f.createdAt} = ${after.starredAt}::timestamptz and ${f.segmentId} > ${after.segmentId}::uuid))`
            : undefined,
        ),
      )
      .orderBy(desc(f.createdAt), asc(f.segmentId))
      .limit(limit + 1);
  }
}
