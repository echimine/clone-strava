import { ConflictException, Inject, Injectable } from "@nestjs/common";
import type { Database } from "@repo/db";
import type { CreateItineraryRequest, Itinerary } from "@repo/contracts";
import { DATABASE } from "../../infrastructure/index.js";
import { ItineraryGeometryRepository } from "../repositories/itinerary-geometry.repository.js";
import { ItineraryRepository } from "../repositories/itinerary.repository.js";
import { ItineraryLifecycleEvents } from "../services/itinerary-lifecycle-events.service.js";
import { ItinerarySaveService } from "../services/itinerary-save.service.js";
import { GetItineraryUseCase } from "./get-itinerary.use-case.js";

export interface CreateItineraryResult {
  itinerary: Itinerary;
  /** `true` -> `201`; `false` -> `200`, a replayed call that wrote nothing. */
  created: boolean;
}

/**
 * `POST /v1/itineraries` (ADR-030 §5, §6): idempotent on the app-generated
 * id. A replay by the same athlete returns the stored Itinerary without
 * computing or writing anything; someone else's id is a `409`. Otherwise
 * the save computation runs, then `itinerary`, its Waypoints and its Legs
 * are written in one transaction. The lifecycle events follow the commit
 * only; a replay emits nothing.
 */
@Injectable()
export class CreateItineraryUseCase {
  constructor(
    @Inject(DATABASE) private readonly db: Database,
    private readonly itineraries: ItineraryRepository,
    private readonly geometries: ItineraryGeometryRepository,
    private readonly save: ItinerarySaveService,
    private readonly getItinerary: GetItineraryUseCase,
    private readonly lifecycle: ItineraryLifecycleEvents,
  ) {}

  async execute(userId: string, request: CreateItineraryRequest): Promise<CreateItineraryResult> {
    const ownerId = await this.itineraries.findOwnerId(request.id);
    if (ownerId !== undefined) {
      return this.replay(userId, ownerId, request.id);
    }

    const prepared = await this.lifecycle.trackSaveFailure(userId, () => this.save.prepare(request));
    const inserted = await this.db.transaction(async (tx) => {
      const isNew = await this.itineraries.insertIfAbsent({ id: request.id, userId, ...prepared.values }, tx);
      if (isNew) {
        await this.geometries.replace(request.id, prepared, tx);
      }
      return isNew;
    });
    if (!inserted) {
      // Lost a race with a concurrent call carrying the same id.
      return this.replay(userId, (await this.itineraries.findOwnerId(request.id))!, request.id);
    }
    const itinerary = await this.getItinerary.execute(userId, request.id);
    this.lifecycle.created(userId, itinerary, prepared.sportCategory);
    return { itinerary, created: true };
  }

  private async replay(userId: string, ownerId: string, id: string): Promise<CreateItineraryResult> {
    if (ownerId !== userId) {
      throw new ConflictException({ code: "id_conflict", message: "This id is already used" });
    }
    return { itinerary: await this.getItinerary.execute(userId, id), created: false };
  }
}
