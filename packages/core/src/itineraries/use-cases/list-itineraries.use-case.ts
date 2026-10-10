import { Injectable, UnprocessableEntityException } from "@nestjs/common";
import type { ListItinerariesQuery, ListItinerariesResponse } from "@repo/contracts";
import {
  decodeItineraryCursor,
  encodeItineraryCursor,
  InvalidItineraryCursorError,
  type ItineraryCursor,
} from "../domain/itinerary-cursor.js";
import { toItinerarySummary } from "../domain/itinerary-view.js";
import { ItineraryRepository } from "../repositories/itinerary.repository.js";

/**
 * `GET /v1/itineraries` (ADR-030 §6): the athlete's own Itineraries, most
 * recently updated first, keyset-paginated on `(updated_at desc, id)`.
 * A cursor this server did not produce answers `422 invalid_cursor`.
 */
@Injectable()
export class ListItinerariesUseCase {
  constructor(private readonly itineraries: ItineraryRepository) {}

  async execute(userId: string, query: ListItinerariesQuery): Promise<ListItinerariesResponse> {
    const after = query.cursor === undefined ? undefined : this.decode(query.cursor);
    const rows = await this.itineraries.findPage({ userId, after, limit: query.limit });
    const page = rows.slice(0, query.limit);
    const last = page.at(-1);
    return {
      items: page.map(toItinerarySummary),
      nextCursor:
        rows.length > query.limit && last
          ? encodeItineraryCursor({ updatedAt: last.cursorUpdatedAt, id: last.id })
          : null,
    };
  }

  private decode(cursor: string): ItineraryCursor {
    try {
      return decodeItineraryCursor(cursor);
    } catch (error) {
      if (error instanceof InvalidItineraryCursorError) {
        throw new UnprocessableEntityException({ code: "invalid_cursor", message: "Invalid itinerary cursor" });
      }
      throw error;
    }
  }
}
