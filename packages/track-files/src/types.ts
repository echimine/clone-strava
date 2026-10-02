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
