import { Injectable, NotFoundException } from "@nestjs/common";
import type { Itinerary } from "@repo/contracts";
import { toItinerary } from "../domain/itinerary-view.js";
import { ItineraryGeometryRepository } from "../repositories/itinerary-geometry.repository.js";
import { ItineraryRepository } from "../repositories/itinerary.repository.js";

/**
 * `GET /v1/itineraries/:id` (ADR-030 §6). Someone else's Itinerary
 * answers `404`, like an unknown one, never `403`.
 */
@Injectable()
export class GetItineraryUseCase {
  constructor(
    private readonly itineraries: ItineraryRepository,
    private readonly geometries: ItineraryGeometryRepository,
  ) {}

  async execute(userId: string, itineraryId: string): Promise<Itinerary> {
    const row = await this.itineraries.findOwned(userId, itineraryId);
    if (!row) {
      throw new NotFoundException({ code: "not_found", message: "Itinerary not found" });
    }
    return toItinerary({ ...row, ...(await this.geometries.find(itineraryId)) });
  }
}
