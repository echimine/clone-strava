import type { LonLat } from "@repo/geo";

/** EWKT accepted by the PostGIS `geometry(LineString, 4326)` column (ADR-017). */
export function toLineStringEwkt(points: LonLat[]): string {
  return `SRID=4326;LINESTRING(${points.map((p) => `${p.lon} ${p.lat}`).join(",")})`;
}

/** EWKT accepted by the PostGIS `geometry(Point, 4326)` column (ADR-017). */
export function toPointEwkt(point: LonLat): string {
  return `SRID=4326;POINT(${point.lon} ${point.lat})`;
}
