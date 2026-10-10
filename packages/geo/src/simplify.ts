import type { LonLat } from "./types.js";

const METERS_PER_DEGREE = 111_320;

/**
 * Douglas-Peucker simplification of a track (ADR-019 §5 step 5), with a
 * tolerance in meters. Uses a local equirectangular projection, accurate
 * enough at activity scale. Returns a subset of the input points, unchanged.
 */
export function simplifyTrack<T extends LonLat>(points: T[], toleranceM: number): T[] {
  if (points.length <= 2) {
    return points;
  }
  const cosLat = Math.cos((points[0]!.lat * Math.PI) / 180);
  const xy = points.map((p) => ({ x: p.lon * METERS_PER_DEGREE * cosLat, y: p.lat * METERS_PER_DEGREE }));
  const keep = new Uint8Array(points.length);
  keep[0] = 1;
  keep[points.length - 1] = 1;

  // Iterative to avoid deep recursion on long traces.
  const stack: Array<[number, number]> = [[0, points.length - 1]];
  while (stack.length > 0) {
    const [first, last] = stack.pop()!;
    let maxDistance = 0;
    let index = -1;
    for (let i = first + 1; i < last; i++) {
      const distance = perpendicularDistance(xy[i]!, xy[first]!, xy[last]!);
      if (distance > maxDistance) {
        maxDistance = distance;
        index = i;
      }
    }
    if (index !== -1 && maxDistance > toleranceM) {
      keep[index] = 1;
      stack.push([first, index], [index, last]);
    }
  }
  return points.filter((_, i) => keep[i] === 1);
}

function perpendicularDistance(
  p: { x: number; y: number },
  a: { x: number; y: number },
  b: { x: number; y: number },
): number {
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  const lengthSquared = dx * dx + dy * dy;
  if (lengthSquared === 0) {
    return Math.hypot(p.x - a.x, p.y - a.y);
  }
  const t = Math.max(0, Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared));
  return Math.hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy));
}
