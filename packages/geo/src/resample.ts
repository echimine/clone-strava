import { haversineDistanceM } from "./distance.js";
import type { GeoPoint } from "./types.js";

/** Below this, a step landing on a vertex is treated as landing on it exactly. */
const EPSILON_M = 1e-9;

/**
 * Points every `stepM` meters along a track, measured along the track
 * (ADR-030 §3, §7), from its first point; the last point of the track is
 * always kept, so the result keeps the track's length. Positions are
 * interpolated linearly inside each leg, which is accurate at step scale.
 * The altitude is interpolated when both ends of the leg have one, and
 * left out otherwise. Only `lat`, `lon` and `elevationM` are returned.
 */
export function resampleAlongTrack(points: GeoPoint[], stepM: number): GeoPoint[] {
  if (!(stepM > 0) || !Number.isFinite(stepM)) {
    throw new RangeError(`stepM must be a positive finite number, got ${stepM}`);
  }
  if (points.length === 0) {
    return [];
  }

  const resampled: GeoPoint[] = [pointAt(points[0]!, points[0]!, 0)];
  let legStartM = 0;
  let nextM = stepM;
  for (let i = 1; i < points.length; i++) {
    const a = points[i - 1]!;
    const b = points[i]!;
    const legM = haversineDistanceM(a, b);
    while (nextM < legStartM + legM - EPSILON_M) {
      resampled.push(pointAt(a, b, (nextM - legStartM) / legM));
      nextM += stepM;
    }
    legStartM += legM;
  }
  if (points.length > 1) {
    resampled.push(pointAt(points.at(-1)!, points.at(-1)!, 0));
  }
  return resampled;
}

function pointAt(a: GeoPoint, b: GeoPoint, t: number): GeoPoint {
  const point: GeoPoint = { lat: a.lat + (b.lat - a.lat) * t, lon: a.lon + (b.lon - a.lon) * t };
  if (a.elevationM !== undefined && b.elevationM !== undefined) {
    point.elevationM = a.elevationM + (b.elevationM - a.elevationM) * t;
  }
  return point;
}
