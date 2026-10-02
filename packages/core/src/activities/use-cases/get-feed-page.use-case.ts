import { Injectable, UnprocessableEntityException } from "@nestjs/common";
import { SocialService } from "../../social/index.js";
import { ActivityRepository } from "../repositories/activity.repository.js";
import { ActivityStatsRepository } from "../repositories/activity-stats.repository.js";
import { ActivityTrackRepository } from "../repositories/activity-track.repository.js";
import { decodeFeedCursor, encodeFeedCursor, InvalidFeedCursorError, type FeedCursor } from "../domain/feed-cursor.js";
import type { FeedActivity, FeedActivityPage } from "../domain/feed-activity.js";

/**
 * Feed steps 1-2 of ADR-021 §6 (ADR-029): followees, then one keyset page of
 * activities with their stats and map fields, each read from this module's
 * own tables. Authors and engagement counts are composed by the caller.
 */
@Injectable()
export class GetFeedPageUseCase {
  constructor(
    private readonly social: SocialService,
    private readonly activities: ActivityRepository,
    private readonly stats: ActivityStatsRepository,
    private readonly tracks: ActivityTrackRepository,
  ) {}

  async execute(viewerId: string, query: { cursor?: string; limit: number }): Promise<FeedActivityPage> {
    const before = query.cursor ? this.decode(query.cursor) : undefined;
    const followeeIds = await this.social.getFolloweeIds(viewerId);
    const rows = await this.activities.findFeedPage({ viewerId, followeeIds, before, limit: query.limit });
    const page = rows.slice(0, query.limit);
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
        },
        mapPolyline: track?.mapPolyline ?? null,
        locationName: track?.locationName ?? null,
      };
    });

    const last = page.at(-1);
    const nextCursor =
      rows.length > query.limit && last ? encodeFeedCursor({ startedAt: last.startedAt, id: last.id }) : null;
    return { items, nextCursor };
  }

  private decode(cursor: string): FeedCursor {
    try {
      return decodeFeedCursor(cursor);
    } catch (error) {
      if (error instanceof InvalidFeedCursorError) {
        throw new UnprocessableEntityException({ code: "invalid_cursor", message: "Invalid feed cursor" });
      }
      throw error;
    }
  }
}
