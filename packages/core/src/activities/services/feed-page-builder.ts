import { Injectable, UnprocessableEntityException } from "@nestjs/common";
import type { schema } from "@repo/db";
import { ActivityStatsRepository } from "../repositories/activity-stats.repository.js";
import { ActivityTrackRepository } from "../repositories/activity-track.repository.js";
import { decodeFeedCursor, encodeFeedCursor, InvalidFeedCursorError, type FeedCursor } from "../domain/feed-cursor.js";
import type { FeedActivity, FeedActivityPage } from "../domain/feed-activity.js";

type ActivityRow = typeof schema.activity.$inferSelect;

/**
 * Shared by every keyset list of Activities (the feed, ADR-029, and an athlete's Activities,
 * ADR-036 §3): decodes the cursor, then turns up to `limit + 1` rows into a page with their
 * stats and map fields, each read from this module's own tables.
 */
@Injectable()
export class FeedPageBuilder {
  constructor(
    private readonly stats: ActivityStatsRepository,
    private readonly tracks: ActivityTrackRepository,
  ) {}

  /** `422 invalid_cursor` for a cursor this server did not produce. */
  decodeCursor(cursor: string | undefined): FeedCursor | undefined {
    if (cursor === undefined) {
      return undefined;
    }
    try {
      return decodeFeedCursor(cursor);
    } catch (error) {
      if (error instanceof InvalidFeedCursorError) {
        throw new UnprocessableEntityException({ code: "invalid_cursor", message: "Invalid feed cursor" });
      }
      throw error;
    }
  }

  /** `rows` hold up to `limit + 1` Activities, newest first: the extra one only says a next page exists. */
  async build(rows: ActivityRow[], limit: number): Promise<FeedActivityPage> {
    const page = rows.slice(0, limit);
    const ids = page.map((row) => row.id);

    const [statsRows, trackRows] = await Promise.all([
      this.stats.findByActivityIds(ids),
      this.tracks.findFeedFieldsByActivityIds(ids),
    ]);
    const statsById = new Map(statsRows.map((row) => [row.activityId, row]));
    const tracksById = new Map(trackRows.map((row) => [row.activityId, row]));

    const items: FeedActivity[] = page.map((row) => {
      const stats = statsById.get(row.id);
      const track = tracksById.get(row.id);
      return {
        id: row.id,
        userId: row.userId,
        sportTypeCode: row.sportTypeCode,
        visibility: row.visibility,
        processingStatus: row.processingStatus,
        startedAt: row.startedAt,
        title: row.title,
        stats: {
          distanceM: stats?.distanceM ?? null,
          movingTimeS: stats?.movingTimeS ?? null,
          elapsedTimeS: stats?.elapsedTimeS ?? null,
          elevationGainM: stats?.elevationGainM ?? null,
          avgSpeedMs: stats?.avgSpeedMs ?? null,
        },
        mapPolyline: track?.mapPolyline ?? null,
        locationName: track?.locationName ?? null,
        routeTrimmed: track?.routeTrimmed ?? false,
      };
    });

    const last = page.at(-1);
    const nextCursor =
      rows.length > limit && last ? encodeFeedCursor({ startedAt: last.startedAt, id: last.id }) : null;
    return { items, nextCursor };
  }
}
