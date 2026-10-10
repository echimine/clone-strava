import { Inject, Injectable } from "@nestjs/common";
import type { Database } from "@repo/db";
import type { Itinerary, SaveItineraryRequest } from "@repo/contracts";
import { DATABASE } from "../../infrastructure/index.js";
import { ItineraryGeometryRepository } from "../repositories/itinerary-geometry.repository.js";
import { ItineraryRepository } from "../repositories/itinerary.repository.js";
import { ItineraryLifecycleEvents } from "../services/itinerary-lifecycle-events.service.js";
import { ItinerarySaveService } from "../services/itinerary-save.service.js";
import { GetItineraryUseCase } from "./get-itinerary.use-case.js";
import { itineraryNotFound } from "./itinerary-not-found.js";

/**
 * `PUT /v1/itineraries/:id` (ADR-030 §6): full replacement of name, sport,
 * Waypoints and Legs, with the full computation (altitudes included) run
 * again. The `itinerary` row, its Waypoints and its Legs are written in one
 * transaction. Unknown or someone else's Itinerary: `404`, checked before
 * computing anything. A `422` or `503` writes nothing. Returns only once the
 * transaction has committed, after its lifecycle events: a returned
 * Itinerary is always a write.
 */
@Injectable()
export class UpdateItineraryUseCase {
  constructor(
    @Inject(DATABASE) private readonly db: Database,
    private readonly itineraries: ItineraryRepository,
    private readonly geometries: ItineraryGeometryRepository,
    private readonly save: ItinerarySaveService,
    private readonly getItinerary: GetItineraryUseCase,
    private readonly lifecycle: ItineraryLifecycleEvents,
  ) {}

  async execute(userId: string, itineraryId: string, request: SaveItineraryRequest): Promise<Itinerary> {
    if ((await this.itineraries.findOwnerId(itineraryId)) !== userId) {
      throw itineraryNotFound();
    }

    const prepared = await this.lifecycle.trackSaveFailure(userId, () => this.save.prepare(request));
    const updated = await this.db.transaction(async (tx) => {
      const found = await this.itineraries.update(userId, itineraryId, prepared.values, tx);
      if (found) {
        await this.geometries.replace(itineraryId, prepared, tx);
      }
      return found;
    });
    if (!updated) {
      // Deleted while the computation was running.
      throw itineraryNotFound();
    }
    const itinerary = await this.getItinerary.execute(userId, itineraryId);
    this.lifecycle.updated(userId, itinerary, prepared.sportCategory);
    return itinerary;
  }
}
