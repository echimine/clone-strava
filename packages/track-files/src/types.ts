// Public types of @repo/track-files (ADR-028 §5). No business rule lives here.

export type TrackFileFormat = "gpx" | "tcx" | "fit";

export interface ParsedTrackPoint {
  /** Degrees, WGS84. */
  lat: number;
  lon: number;
  elevationM?: number;
  /** UTC epoch ms; undefined if the file carries no time. */
  timestampMs?: number;
  heartRateBpm?: number;
  cadenceRpm?: number;
  speedMs?: number;
}

export interface ParsedTrackFile {
  /** Format detected from the content. */
  format: TrackFileFormat;
  /** Only points that have coordinates. */
  points: ParsedTrackPoint[];
  /** Samples dropped for lacking lat/lon (indoor). */
  pointsWithoutPosition: number;
  name?: string;
  /** Raw sport string from the file, lowercased. */
  sport?: string;
  startedAtMs?: number;
  endedAtMs?: number;
  /** FIT pool swim (sub-sport `lap_swimming`) only: the pool and its lengths (ADR-039 §4). */
  pool?: ParsedPool;
}

/** A length of the pool as the FIT `length` message gives it; it carries no distance. */
export interface ParsedLength {
  /** UTC epoch ms. */
  startMs: number;
  /** `totalElapsedTime`, seconds. */
  elapsedS: number;
  /** `lengthType`: `active` (strokes) or `idle` (a rest). */
  active: boolean;
}

export interface ParsedPool {
  /** `session.pool_length`, always in meters (25 yards are 22.86). */
  lengthM: number;
  /** `session.pool_length_unit`: how the pool was set on the watch. */
  unit: "metric" | "statute";
  /** In file order. */
  lengths: ParsedLength[];
}

export interface ParseOptions {
  declaredFormat?: TrackFileFormat;
  /** Default 200_000 (ADR-028 §5). */
  maxPoints?: number;
}

export type TrackFileErrorCode = "invalid_file" | "unsupported_format" | "too_many_points";

export class TrackFileError extends Error {
  constructor(
    public readonly code: TrackFileErrorCode,
    message: string,
  ) {
    super(message);
    this.name = "TrackFileError";
  }
}

export const DEFAULT_MAX_POINTS = 200_000;
