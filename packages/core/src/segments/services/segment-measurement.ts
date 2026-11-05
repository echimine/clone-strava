import { Injectable, ServiceUnavailableException } from "@nestjs/common";
import { encodePolyline, encodeWithinBudget, trackDistanceM, type LonLat } from "@repo/geo";
import type { SegmentTrack } from "@repo/contracts";
import { ElevationService, ElevationUnavailableError } from "../../elevation/index.js";
import {
  resampleSegmentTrack,
  segmentFigures,
  segmentRuleViolations,
  type SegmentFigures,
  type SegmentRuleViolation,
} from "../domain/segment-geometry.js";

/** Budget of `map_polyline`, as for an Itinerary (ADR-030 §5): a Mapbox Static Images URL. */
const MAP_POLYLINE_MAX_CHARS = 2000;

/** Everything the server computes from a drawn path, once (ADR-039 §5). */
export interface SegmentMeasurement {
  violations: SegmentRuleViolation[];
  figures: SegmentFigures;
  /** Points every ~20 m with the `ElevationService`'s altitudes: the stored `LineStringZ`. */
  track: Array<LonLat & { altitudeM: number }>;
  /** The track as answered: polyline6 and altitudes. */
  trackView: SegmentTrack;
  /** polyline5 for the map cards. */
  mapPolyline: string;
}

/**
 * The single computation of a Segment, shared by preview and creation so the previewed figures
 * are the stored ones: rules on the drawn path, resampling every ~20 m, altitudes from the
 * `ElevationService` (never the GPS), then the figures. A failing provider answers a retryable
 * `503 elevation_unavailable`, as for the Itineraries.
 */
@Injectable()
export class SegmentMeasurementService {
  constructor(private readonly elevation: ElevationService) {}

  async measure(sport: string, points: LonLat[]): Promise<SegmentMeasurement> {
    const resampled = resampleSegmentTrack(points);
    const elevations = await this.elevationsOf(resampled);
    const track = resampled.map((point, i) => ({ ...point, altitudeM: Math.round(elevations[i]!.altitudeM * 10) / 10 }));
    return {
      violations: segmentRuleViolations(sport, points),
      figures: segmentFigures(trackDistanceM(points), track),
      track,
      trackView: { polyline6: encodePolyline(track, 6), altitudesM: track.map((point) => point.altitudeM) },
      mapPolyline: encodeWithinBudget(track, { maxChars: MAP_POLYLINE_MAX_CHARS, firstToleranceM: 5 }),
    };
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
