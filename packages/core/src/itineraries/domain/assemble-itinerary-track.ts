import { decodePolyline, haversineDistanceM, InvalidPolylineError, trackDistanceM, type LonLat } from "@repo/geo";
import type { ItineraryGeometry, ItineraryLegMode } from "@repo/contracts";
import { ITINERARY_LIMITS } from "./itinerary-limits.js";
import { ItineraryValidationError } from "./itinerary-validation-error.js";

/** A Leg with its 2D path: decoded for `follow`, drawn by the server for `straight`. */
export interface AssembledLeg {
  mode: ItineraryLegMode;
  path: LonLat[];
}

export interface AssembledItinerary {
  waypoints: LonLat[];
  legs: AssembledLeg[];
  /** The Legs joined end to end, the junction point kept once. */
  track: LonLat[];
  /** Exact length of `track` (haversine), in meters. */
  distanceM: number;
}

/**
 * Step 1 and 2 of the single Itinerary computation (ADR-030 §3): checks the
 * geometry invariants, assembles the Legs into one 2D track and measures
 * it. Throws `ItineraryValidationError` on the first violated invariant.
 */
export function assembleItineraryTrack(geometry: ItineraryGeometry): AssembledItinerary {
  const { waypoints } = geometry;
  const { minWaypoints, maxWaypoints, maxDecodedPoints, maxDistanceM } = ITINERARY_LIMITS;
  if (waypoints.length < minWaypoints || waypoints.length > maxWaypoints) {
    throw new ItineraryValidationError("waypoints", `An Itinerary has ${minWaypoints} to ${maxWaypoints} Waypoints`);
  }
  if (geometry.legs.length !== waypoints.length - 1) {
    throw new ItineraryValidationError("legs", "An Itinerary has exactly one Leg fewer than Waypoints");
  }

  let decodedPoints = 0;
  const legs = geometry.legs.map((leg, index): AssembledLeg => {
    const from = waypoints[index]!;
    const to = waypoints[index + 1]!;
    if (leg.mode === "straight") {
      return { mode: "straight", path: [from, to] };
    }
    const path = decodeLeg(leg.polyline6, index);
    decodedPoints += path.length;
    if (decodedPoints > maxDecodedPoints) {
      throw new ItineraryValidationError("legs", `An Itinerary has at most ${maxDecodedPoints} decoded points`);
    }
    checkEndpoint(path[0]!, from, `legs.${index}.polyline6`, "start");
    checkEndpoint(path.at(-1)!, to, `legs.${index}.polyline6`, "end");
    return { mode: "follow", path };
  });

  const track = joinPaths(legs.map((leg) => leg.path));
  const distanceM = trackDistanceM(track);
  if (distanceM > maxDistanceM) {
    throw new ItineraryValidationError("legs", `An Itinerary is at most ${maxDistanceM / 1000} km long`);
  }
  return { waypoints, legs, track, distanceM };
}

function decodeLeg(polyline6: string, index: number): LonLat[] {
  const field = `legs.${index}.polyline6`;
  let path: LonLat[];
  try {
    path = decodePolyline(polyline6, 6);
  } catch (error) {
    if (error instanceof InvalidPolylineError) {
      throw new ItineraryValidationError(field, "Invalid polyline6");
    }
    throw error;
  }
  if (path.length < 2 || path.some((point) => Math.abs(point.lat) > 90 || Math.abs(point.lon) > 180)) {
    throw new ItineraryValidationError(field, "A follow Leg has at least 2 points, in WGS 84 range");
  }
  return path;
}

function checkEndpoint(point: LonLat, waypoint: LonLat, field: string, end: "start" | "end"): void {
  const tolerance = ITINERARY_LIMITS.legEndpointToleranceM;
  if (haversineDistanceM(point, waypoint) > tolerance) {
    throw new ItineraryValidationError(field, `The ${end} of a follow Leg must be within ${tolerance} m of its Waypoint`);
  }
}

/**
 * Concatenates consecutive paths. A path starting exactly where the
 * previous one ended does not repeat that point; otherwise (a `follow`
 * Leg ending a few meters from its Waypoint) the gap is joined by a
 * straight segment, which counts in the distance.
 */
function joinPaths(paths: LonLat[][]): LonLat[] {
  const track: LonLat[] = [];
  for (const path of paths) {
    const last = track.at(-1);
    const first = path[0]!;
    const skipFirst = last !== undefined && last.lat === first.lat && last.lon === first.lon;
    for (const point of skipFirst ? path.slice(1) : path) {
      track.push({ lat: point.lat, lon: point.lon });
    }
  }
  return track;
}
