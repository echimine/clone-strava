import { TRACE_SCHEMA_VERSION, type ActivityImportErrorCode, type Trace } from "@repo/contracts";
import type { ParsedPool, ParsedTrackFile } from "@repo/track-files";

/** Result of turning a parsed file into an activity trace (ADR-028 §4 steps 5-6). */
export type ImportTraceResult =
  | { ok: true; trace: Trace; startedAt: Date; endedAt: Date }
  | { ok: false; code: ActivityImportErrorCode };

/**
 * Activity-specific rules on top of `@repo/track-files`, which applies
 * none (ADR-028 §5): every point needs a timestamp, at least two points
 * with coordinates, and a positive duration. The minimum duration of the
 * sport is checked by the caller once the sport is known.
 */
export function toImportTrace(parsed: ParsedTrackFile): ImportTraceResult {
  if (parsed.pool) {
    return toPoolTrace(parsed, parsed.pool);
  }
  if (parsed.points.length === 0) {
    return { ok: false, code: parsed.pointsWithoutPosition > 0 ? "no_gps_data" : "empty_track" };
  }
  if (parsed.points.some((point) => point.timestampMs === undefined)) {
    return { ok: false, code: "no_timestamps" };
  }
  if (parsed.points.length < 2) {
    return { ok: false, code: "empty_track" };
  }

  const points = parsed.points
    .map((point) => ({
      timestampMs: point.timestampMs!,
      lat: point.lat,
      lon: point.lon,
      elevationM: point.elevationM,
      speedMs: point.speedMs !== undefined && point.speedMs >= 0 ? point.speedMs : undefined,
      heartRateBpm:
        point.heartRateBpm !== undefined && point.heartRateBpm > 0
          ? Math.round(point.heartRateBpm)
          : undefined,
      cadenceRpm: point.cadenceRpm !== undefined && point.cadenceRpm >= 0 ? point.cadenceRpm : undefined,
    }))
    .sort((a, b) => a.timestampMs - b.timestampMs);

  const startedAtMs = Math.min(parsed.startedAtMs ?? Infinity, points[0]!.timestampMs);
  const endedAtMs = Math.max(parsed.endedAtMs ?? -Infinity, points[points.length - 1]!.timestampMs);
  if (!(endedAtMs > startedAtMs)) {
    return { ok: false, code: "invalid_duration" };
  }

  return {
    ok: true,
    trace: { schemaVersion: TRACE_SCHEMA_VERSION, points, pauses: [] },
    startedAt: new Date(startedAtMs),
    endedAt: new Date(endedAtMs),
  };
}

/**
 * A pool swim (ADR-039 §4): accepted without positions, the trace keeps its lengths and pool
 * instead of points. Without an active length it is just another file without positions.
 */
function toPoolTrace(parsed: ParsedTrackFile, pool: ParsedPool): ImportTraceResult {
  const lengths = pool.lengths.map((length) => ({
    startMs: Math.round(length.startMs),
    elapsedMs: Math.round(length.elapsedS * 1000),
    active: length.active,
  }));
  if (!lengths.some((length) => length.active)) {
    return { ok: false, code: "no_gps_data" };
  }
  const first = lengths[0]!;
  const last = lengths[lengths.length - 1]!;
  const startedAtMs = Math.min(parsed.startedAtMs ?? Infinity, first.startMs);
  const endedAtMs = Math.max(parsed.endedAtMs ?? -Infinity, last.startMs + last.elapsedMs);
  if (!(endedAtMs > startedAtMs)) {
    return { ok: false, code: "invalid_duration" };
  }
  return {
    ok: true,
    trace: {
      schemaVersion: TRACE_SCHEMA_VERSION,
      points: [],
      pauses: [],
      pool: { lengthM: pool.lengthM, unit: pool.unit === "statute" ? "yd" : "m" },
      lengths,
    },
    startedAt: new Date(startedAtMs),
    endedAt: new Date(endedAtMs),
  };
}
