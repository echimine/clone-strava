import type { LonLat } from "@repo/geo";

/**
 * PostGIS formats of the `itineraries` geometries (ADR-017: SRID 4326):
 * EWKT on write, `ST_AsGeoJSON` on read.
 */

/** EWKT accepted by `geometry(Point, 4326)`. */
export function toPointEwkt(point: LonLat): string {
  return `SRID=4326;POINT(${point.lon} ${point.lat})`;
}

/** EWKT accepted by `geometry(LineString, 4326)`. */
export function toLineStringEwkt(points: LonLat[]): string {
  return `SRID=4326;LINESTRING(${points.map((p) => `${p.lon} ${p.lat}`).join(",")})`;
}

/** EWKT accepted by `geometry(LineStringZ, 4326)`: Z is the altitude (ADR-030 §5). */
export function toLineStringZEwkt(points: (LonLat & { altitudeM: number })[]): string {
  return `SRID=4326;LINESTRING Z(${points.map((p) => `${p.lon} ${p.lat} ${p.altitudeM}`).join(",")})`;
}

/** An `ST_AsGeoJSON` Point. */
export function parseGeoJsonPoint(geoJson: string): LonLat {
  const [lon, lat] = (JSON.parse(geoJson) as { coordinates: number[] }).coordinates;
  return { lat: lat!, lon: lon! };
}

/** An `ST_AsGeoJSON` LineString (2D). */
export function parseGeoJsonLineString(geoJson: string): LonLat[] {
  return parseGeoJsonLineStringZ(geoJson).map(({ lat, lon }) => ({ lat, lon }));
}

/** An `ST_AsGeoJSON` LineStringZ: Z is the altitude. */
export function parseGeoJsonLineStringZ(geoJson: string): (LonLat & { altitudeM: number })[] {
  const positions = (JSON.parse(geoJson) as { coordinates: number[][] }).coordinates;
  return positions.map(([lon, lat, z]) => ({ lat: lat!, lon: lon!, altitudeM: z ?? 0 }));
}
