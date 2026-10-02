import type { LonLat } from "./simplify-route.js";

/**
 * Google encoded polyline algorithm (ADR-029), the format the Mapbox Static
 * Images `path` overlay accepts. Coordinates are emitted as `lat,lon` pairs
 * with `precision` decimal digits (5 = polyline5).
 */
export function encodePolyline(points: LonLat[], precision = 5): string {
  const factor = 10 ** precision;
  let previousLat = 0;
  let previousLon = 0;
  let output = "";
  for (const point of points) {
    const lat = Math.round(point.lat * factor);
    const lon = Math.round(point.lon * factor);
    output += encodeSigned(lat - previousLat) + encodeSigned(lon - previousLon);
    previousLat = lat;
    previousLon = lon;
  }
  return output;
}

function encodeSigned(value: number): string {
  let rest = value < 0 ? ~(value << 1) : value << 1;
  let output = "";
  while (rest >= 0x20) {
    output += String.fromCharCode((0x20 | (rest & 0x1f)) + 63);
    rest >>= 5;
  }
  return output + String.fromCharCode(rest + 63);
}
