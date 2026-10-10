import { Injectable, ServiceUnavailableException, UnprocessableEntityException } from "@nestjs/common";
import { elevationGainM, resampleAlongTrack, type LonLat } from "@repo/geo";
import type { ItineraryGeometry, ItineraryMetrics } from "@repo/contracts";
import { ElevationService, ElevationUnavailableError } from "../../elevation/index.js";
import { assembleItineraryTrack, type AssembledLeg } from "../domain/assemble-itinerary-track.js";
import { itineraryElevationSource, roundToDecimeter } from "../domain/itinerary-elevation.js";
import { ITINERARY_HYSTERESIS_M, ITINERARY_RESAMPLE_STEP_M } from "../domain/itinerary-limits.js";
import { ItineraryValidationError } from "../domain/itinerary-validation-error.js";

/** A point of the resampled track, with its altitude (the stored `LineStringZ`). */
export interface ItineraryTrackPoint extends LonLat {
  altitudeM: number;
}

/** Everything a save stores about the geometry, and what a preview returns (`metrics`). */
export interface ItineraryMeasurement {
  metrics: ItineraryMetrics;
  waypoints: LonLat[];
  legs: AssembledLeg[];
  /** Points every ~20 m along the track, with altitudes. */
  track: ItineraryTrackPoint[];
}

/**
 * The single Itinerary computation (ADR-030 §3), shared by save and
 * preview so the previewed figures are the stored ones:
 *  1. assemble the Legs into one 2D track (straight Legs drawn here);
 *  2. distance on that exact track;
 *  3. resample every ~20 m;
 *  4. altitudes of the resampled points (`elevation` module);
 *  5. gain with a 2 m hysteresis.
 * Throws `422 validation_error` on a violated invariant and a retryable
 * `503 elevation_unavailable` when an elevation provider fails.
 */
@Injectable()
export class ItineraryMeasurementService {
  constructor(private readonly elevation: ElevationService) {}

  async measure(geometry: ItineraryGeometry): Promise<ItineraryMeasurement> {
    const assembled = this.assemble(geometry);
    const resampled = resampleAlongTrack(assembled.track, ITINERARY_RESAMPLE_STEP_M);
    const elevations = await this.elevationsOf(resampled);
    const track = resampled.map((point, i) => ({ lat: point.lat, lon: point.lon, altitudeM: elevations[i]!.altitudeM }));
    return {
      metrics: {
        distanceM: roundToDecimeter(assembled.distanceM),
        elevationGainM: roundToDecimeter(elevationGainM(track.map((point) => point.altitudeM), ITINERARY_HYSTERESIS_M)),
        elevationSource: itineraryElevationSource(elevations.map((elevation) => elevation.source)),
      },
      waypoints: assembled.waypoints,
      legs: assembled.legs,
      track,
    };
  }

  private assemble(geometry: ItineraryGeometry) {
    try {
      return assembleItineraryTrack(geometry);
    } catch (error) {
      if (error instanceof ItineraryValidationError) {
        throw new UnprocessableEntityException({
          code: "validation_error",
          message: error.message,
          details: [{ field: error.field, message: error.message }],
        });
      }
      throw error;
    }
  }

  private async elevationsOf(points: LonLat[]) {
    try {
      return await this.elevation.getElevations(points);
    } catch (error) {
      if (error instanceof ElevationUnavailableError) {
        throw new ServiceUnavailableException(
          { code: "elevation_unavailable", message: "Elevation service unavailable, try again", retryAfterS: error.retryAfterS },
          { cause: error },
        );
      }
      throw error;
    }
  }
}
