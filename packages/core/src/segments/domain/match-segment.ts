/**
 * A single trace point. Deliberately not imported from `activities/domain`
 * (ADR-021 §6, §9.1: a module's `domain/` is pure and self-contained, and
 * cross-module code never reaches into another module's internals — only
 * `index.ts` is public, and `activities` does not export this type there).
 */
export interface TracePoint {
  lat: number;
  lon: number;
  elevationM?: number;
  timestampMs: number;
}

export interface SegmentCandidate {
  segmentId: string;
  path: TracePoint[];
}

export interface SegmentMatch {
  segmentId: string;
  elapsedTimeS: number;
}

/**
 * Checks whether a route actually follows a candidate segment end to end,
 * within tolerance, and if so computes the effort's elapsed time from the
 * raw trace (ADR-019 §8). Pure and DB-free (ADR-021 §6): candidate
 * segments come from a GiST proximity query in the repository, this
 * function only does the geometric comparison.
 *
 * TODO: real matching (resample both lines, compare via a tolerance
 * buffer, ADR-019 §8 "tolerance of a few tens of meters"). Left as a stub
 * for this skeleton.
 */
export function matchSegment(
  _route: TracePoint[],
  _candidate: SegmentCandidate,
  _toleranceM: number,
): SegmentMatch | null {
  throw new Error("not implemented");
}
