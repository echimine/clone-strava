import type { LonLat } from "./types.js";

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

/** Thrown by `decodePolyline` on a string that is not a valid encoded polyline. */
export class InvalidPolylineError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "InvalidPolylineError";
  }
}

/**
 * Inverse of `encodePolyline`: decodes a Google encoded polyline with
 * `precision` decimal digits (5 = polyline5, 6 = polyline6, the Mapbox
 * Directions `geometries=polyline6` format, ADR-030 §2). Input usually
 * comes from a client, so a malformed string (character outside the
 * alphabet, truncated value, latitude without longitude) throws
 * `InvalidPolylineError` instead of yielding garbage.
 */
export function decodePolyline(encoded: string, precision = 5): LonLat[] {
  const factor = 10 ** precision;
  const points: LonLat[] = [];
  const cursor = { index: 0 };
  let lat = 0;
  let lon = 0;
  while (cursor.index < encoded.length) {
    lat += decodeSigned(encoded, cursor);
    if (cursor.index >= encoded.length) {
      throw new InvalidPolylineError("Polyline ends with a latitude without its longitude");
    }
    lon += decodeSigned(encoded, cursor);
    points.push({ lat: lat / factor, lon: lon / factor });
  }
  return points;
}

function decodeSigned(encoded: string, cursor: { index: number }): number {
  let result = 0;
  let shift = 0;
  for (;;) {
    if (cursor.index >= encoded.length) {
      throw new InvalidPolylineError(`Truncated polyline at character ${cursor.index}`);
    }
    const chunk = encoded.charCodeAt(cursor.index) - 63;
    if (chunk < 0 || chunk > 63) {
      throw new InvalidPolylineError(`Invalid polyline character at ${cursor.index}`);
    }
    cursor.index++;
    // Arithmetic instead of `<<`: a value can exceed 31 bits.
    result += (chunk & 0x1f) * 2 ** shift;
    shift += 5;
    if (chunk < 0x20) {
      break;
    }
  }
  return result % 2 === 1 ? -(result + 1) / 2 : result / 2;
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
