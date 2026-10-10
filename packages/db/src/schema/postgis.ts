import { customType } from "drizzle-orm/pg-core";

/**
 * PostGIS geometry columns (ADR-017: SRID 4326 / WGS 84, `geometry(Point,
 * 4326)` and `geometry(LineString, 4326)`, with GiST indexes declared on
 * each table).
 *
 * Modeled as `customType` rather than Drizzle's built-in `geometry()`
 * helper (available since drizzle-orm 0.31) because that helper's `mode`
 * ("xy" | "tuple") only maps `Point`; `LineString` columns (the simplified
 * route, `activity_track.route` / `segment.path`) need the same column type
 * with no built-in TS mapping.
 *
 * `data` is the WKT/EWKT representation (e.g. `SRID=4326;POINT(2.35 48.85)`
 * or `SRID=4326;LINESTRING(...)`), which PostgreSQL/PostGIS accept directly
 * as input for a `geometry` column. On read, PostGIS returns the column's
 * default EWKB hex encoding: callers that need usable coordinates back must
 * wrap the column in `ST_AsText(...)` / `ST_AsGeoJSON(...)` in their query,
 * which is out of scope for this skeleton (`packages/core` modules own that
 * translation).
 */
function geometryType(sqlType: string) {
  return customType<{ data: string }>({
    dataType() {
      return sqlType;
    },
  });
}

/** `geometry(Point, 4326)` column. */
export const geometryPoint = geometryType("geometry(Point,4326)");

/** `geometry(LineString, 4326)` column. */
export const geometryLineString = geometryType("geometry(LineString,4326)");

/** `geometry(LineStringZ, 4326)` column: Z is an altitude in meters (ADR-030 §5). */
export const geometryLineStringZ = geometryType("geometry(LineStringZ,4326)");
