import type { LonLat } from "./types.js";

const EARTH_RADIUS_M = 6371000;

/** Great-circle distance between two points, in meters. */
export function haversineDistanceM(a: LonLat, b: LonLat): number {
  const toRad = (deg: number) => (deg * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLon = toRad(b.lon - a.lon);
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) ** 2;
  return 2 * EARTH_RADIUS_M * Math.asin(Math.sqrt(h));
}

/** Length of a track: the haversine sum of its consecutive legs, in meters. */
export function trackDistanceM(points: LonLat[]): number {
  let distanceM = 0;
  for (let i = 1; i < points.length; i++) {
    distanceM += haversineDistanceM(points[i - 1]!, points[i]!);
  }
  return distanceM;
}
