import { Injectable } from "@nestjs/common";
import { ItineraryRepository } from "../repositories/itinerary.repository.js";
import { itineraryNotFound } from "./itinerary-not-found.js";

/**
 * `DELETE /v1/itineraries/:id` (ADR-030 §6): hard delete (ADR-017), its
 * Waypoints and Legs in cascade. Unknown or someone else's Itinerary
 * (already deleted included): `404`. Resolves only once the row is gone:
 * resolving always means a write.
 */
@Injectable()
export class DeleteItineraryUseCase {
  constructor(private readonly itineraries: ItineraryRepository) {}

  async execute(userId: string, itineraryId: string): Promise<void> {
    if (!(await this.itineraries.delete(userId, itineraryId))) {
      throw itineraryNotFound();
    }
  }
}
