import { Injectable } from "@nestjs/common";
import type { Itinerary } from "@repo/contracts";
import { ItineraryRepository } from "../repositories/itinerary.repository.js";
import { ItineraryLifecycleEvents } from "../services/itinerary-lifecycle-events.service.js";
import { GetItineraryUseCase } from "./get-itinerary.use-case.js";
import { itineraryNotFound } from "./itinerary-not-found.js";

/**
 * `PATCH /v1/itineraries/:id` (ADR-030 §6): renames an Itinerary outside
 * the editor. No recomputation (the `elevation` module is not called);
 * `updated_at` moves. Unknown or someone else's Itinerary: `404`. Returns
 * only once the row is written, after its lifecycle events: a returned
 * Itinerary is always a write.
 */
@Injectable()
export class RenameItineraryUseCase {
  constructor(
    private readonly itineraries: ItineraryRepository,
    private readonly getItinerary: GetItineraryUseCase,
    private readonly lifecycle: ItineraryLifecycleEvents,
  ) {}

  async execute(userId: string, itineraryId: string, name: string): Promise<Itinerary> {
    if (!(await this.itineraries.rename(userId, itineraryId, name))) {
      throw itineraryNotFound();
    }
    const itinerary = await this.getItinerary.execute(userId, itineraryId);
    this.lifecycle.renamed(userId, itinerary);
    return itinerary;
  }
}
