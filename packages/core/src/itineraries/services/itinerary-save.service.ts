import { Injectable, UnprocessableEntityException } from "@nestjs/common";
import type { LonLat } from "@repo/geo";
import type { SaveItineraryRequest } from "@repo/contracts";
import { SportsService } from "../../sports/index.js";
import type { AssembledLeg } from "../domain/assemble-itinerary-track.js";
import { itineraryMapPolyline } from "../domain/itinerary-map-polyline.js";
import type { ItineraryValues } from "../repositories/itinerary.repository.js";
import { ItineraryMeasurementService } from "./itinerary-measurement.service.js";

/** What a full save writes: the `itinerary` columns, then its Waypoints and Legs. */
export interface PreparedItinerary {
  values: ItineraryValues;
  waypoints: LonLat[];
  legs: AssembledLeg[];
}

/**
 * Everything a full save (create, and the full update of ADR-030 §6) does
 * before writing: checks the sport, then runs the single computation
 * shared with `metrics-preview`, so the stored figures are the previewed
 * ones. Throws `422 validation_error` (sport, invariants) or a retryable
 * `503 elevation_unavailable`; writes nothing.
 */
@Injectable()
export class ItinerarySaveService {
  constructor(
    private readonly sports: SportsService,
    private readonly measurement: ItineraryMeasurementService,
  ) {}

  async prepare(request: SaveItineraryRequest): Promise<PreparedItinerary> {
    await this.checkSport(request.sportTypeCode);
    const { metrics, waypoints, legs, track } = await this.measurement.measure(request);
    return {
      values: {
        name: request.name,
        sportTypeCode: request.sportTypeCode,
        ...metrics,
        track,
        mapPolyline: itineraryMapPolyline(track),
      },
      waypoints,
      legs,
    };
  }

  /** ADR-030 §2, §4: an existing, active sport, not a `water` one (no route to follow). */
  private async checkSport(code: string): Promise<void> {
    const sport = await this.sports.findByCode(code);
    if (!sport || !sport.isActive || sport.category === "water") {
      const message = "Unknown sport type, or a sport an Itinerary cannot be planned for";
      throw new UnprocessableEntityException({
        code: "validation_error",
        message,
        details: [{ field: "sportTypeCode", message }],
      });
    }
  }
}
