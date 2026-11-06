import { Injectable, NotFoundException, UnprocessableEntityException } from "@nestjs/common";
import type { ListSegmentFavoritesQuery, ListSegmentFavoritesResponse, SegmentFavorite } from "@repo/contracts";
import {
  decodeFavoriteCursor,
  encodeFavoriteCursor,
  InvalidFavoriteCursorError,
  type FavoriteCursor,
} from "../domain/favorite-cursor.js";
import { SegmentFavoriteRepository, type FavoriteRow } from "../repositories/segment-favorite.repository.js";

/** The star of a Segment (ADR-039 §5): private and free; Plus › « Segments » lists them. */
@Injectable()
export class SegmentFavoritesUseCase {
  constructor(private readonly favorites: SegmentFavoriteRepository) {}

  /** Idempotent; `404 segment_not_found` for an unknown Segment. */
  async favorite(userId: string, segmentId: string): Promise<void> {
    await this.assertExists(segmentId);
    await this.favorites.add(userId, segmentId);
  }

  /** Idempotent; `404 segment_not_found` for an unknown Segment. */
  async unfavorite(userId: string, segmentId: string): Promise<void> {
    await this.assertExists(segmentId);
    await this.favorites.remove(userId, segmentId);
  }

  /** Most recently starred first; `422 invalid_cursor` for a cursor this server did not produce. */
  async list(userId: string, query: ListSegmentFavoritesQuery): Promise<ListSegmentFavoritesResponse> {
    const after = query.cursor === undefined ? undefined : decode(query.cursor);
    const rows = await this.favorites.findPage({ userId, after, limit: query.limit });
    const page = rows.slice(0, query.limit);
    const last = page.at(-1);
    return {
      items: page.map(toFavorite),
      nextCursor:
        rows.length > query.limit && last
          ? encodeFavoriteCursor({ starredAt: last.cursorStarredAt, segmentId: last.id })
          : null,
    };
  }

  private async assertExists(segmentId: string): Promise<void> {
    if (!(await this.favorites.segmentExists(segmentId))) {
      throw new NotFoundException({ code: "segment_not_found", message: "Segment not found" });
    }
  }
}

function decode(cursor: string): FavoriteCursor {
  try {
    return decodeFavoriteCursor(cursor);
  } catch (error) {
    if (error instanceof InvalidFavoriteCursorError) {
      throw new UnprocessableEntityException({ code: "invalid_cursor", message: "Invalid favourites cursor" });
    }
    throw error;
  }
}

function toFavorite(row: FavoriteRow): SegmentFavorite {
  return {
    id: row.id,
    sport: row.sportTypeCode as SegmentFavorite["sport"],
    name: row.name,
    verified: row.verifiedAt !== null,
    distanceM: row.distanceM ?? 0,
    avgGradePct: row.avgGrade ?? 0,
    climbCategory: row.climbCategory,
    myBestTimeS: row.myBestTimeS,
  };
}
