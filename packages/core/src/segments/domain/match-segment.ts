import { haversineDistanceM, resampleAlongTrack, type LonLat } from "@repo/geo";

/**
 * A point of an Activity's cleaned trace (ADR-039 §6). Deliberately not imported from
 * `activities/domain` (ADR-021 §6, §9.1): a module's `domain/` is pure and self-contained.
 */
export interface MatchingPoint extends LonLat {
  timestampMs: number;
}

/** A Pause of a Recording: no point lies strictly inside it (ADR-031 §12). */
export interface MatchingPause {
  startMs: number;
  endMs: number;
}

/** What `matchSegment` reads: the cleaned trace before the privacy zone, with its Pauses. */
export interface MatchingTrace {
  points: MatchingPoint[];
  pauses: MatchingPause[];
}

/** One Effort found on the trace (ADR-039 §6). */
export interface MatchedEffort {
  /** Index of the trace point just before the start crossing. */
  startIndex: number;
  /** Index of the trace point just after the finish crossing. */
  endIndex: number;
  /** Interpolated instant of the start crossing. */
  startedAtMs: number;
  /** Interpolated instant of the finish crossing. */
  endedAtMs: number;
  /** Elapsed time, Pauses included, rounded to the second. */
  elapsedTimeS: number;
  /** Smallest crow-fly distance from the Effort's points to the Activity's first point. */
  minDistanceToActivityStartM: number;
  /** Smallest crow-fly distance from the Effort's points to the Activity's last point. */
  minDistanceToActivityEndM: number;
}

/** Thresholds of the matching (ADR-039 §6): starting values, to calibrate on real traces. */
export interface SegmentMatchingThresholds {
  /** Half-width of the virtual start and finish lines. */
  lineHalfWidthM: number;
  /** Step of the resampling of the Segment and of the candidate portion. */
  resampleStepM: number;
  /** A Segment point is covered when the portion passes within this distance. */
  coverageToleranceM: number;
  /** Share of the Segment's points that must be covered. */
  minCoverage: number;
  /** Largest discrete Fréchet distance between the portion and the Segment. */
  maxFrechetM: number;
  /** Two consecutive points further apart than this make a gap. */
  maxGapM: number;
  /** A move during a Pause longer than this makes a gap. */
  maxPauseMoveM: number;
}

export const SEGMENT_MATCHING_THRESHOLDS: SegmentMatchingThresholds = {
  lineHalfWidthM: 25,
  resampleStepM: 10,
  coverageToleranceM: 25,
  minCoverage: 0.9,
  maxFrechetM: 50,
  maxGapM: 100,
  maxPauseMoveM: 25,
};

/**
 * Bumped whenever the algorithm or its thresholds change: `reconcile-segment-matching` replays
 * every Activity matched with an older version (ADR-039 §6, §13).
 */
export const SEGMENT_MATCHING_VERSION = 1;

/** Distance used to orient the start and finish lines along the Segment. */
const HEADING_SPAN_M = 20;

/**
 * A Segment's path resampled every `stepM` meters, ends kept: by default as `matchSegment`
 * compares it (ADR-039 §6) and for the both-ways duplicate test; every `SEGMENT_TRACK_STEP_M`
 * for the stored path of a new Segment (§5).
 */
export function resampleSegmentPath(path: LonLat[], stepM = SEGMENT_MATCHING_THRESHOLDS.resampleStepM): LonLat[] {
  return resampleAlongTrack(path, stepM).map(({ lat, lon }) => ({ lat, lon }));
}

/**
 * Every Effort of one trace on one Segment (ADR-039 §6), in trace order:
 *  1. oriented crossings of virtual start and finish lines, perpendicular to the Segment;
 *  2. for each start, the first finish after it, then the portion between them, resampled,
 *     must cover the Segment (coverage) in its order (discrete Fréchet);
 *  3. a gap, including a move during a Pause, rejects the portion;
 *  4. each crossing's instant is interpolated; the time is the elapsed time, Pauses included.
 * Two Efforts never overlap: the search resumes after an accepted finish, so a loop ridden
 * three times gives three Efforts. Pure: no I/O.
 */
export function matchSegment(
  trace: MatchingTrace,
  segmentPath: LonLat[],
  thresholds: SegmentMatchingThresholds = SEGMENT_MATCHING_THRESHOLDS,
): MatchedEffort[] {
  const { points, pauses } = trace;
  const segment = resampleSegmentPath(segmentPath, thresholds.resampleStepM);
  if (points.length < 2 || segment.length < 2) {
    return [];
  }
  const frame = localFrame(segment[0]!);
  const segmentXy = segment.map(frame);
  const pointsXy = points.map(frame);
  const headingSteps = Math.max(1, Math.round(HEADING_SPAN_M / thresholds.resampleStepM));
  const startLine = gate(segmentXy[0]!, segmentXy[Math.min(headingSteps, segmentXy.length - 1)]!, "ahead");
  const finishLine = gate(segmentXy.at(-1)!, segmentXy[Math.max(0, segmentXy.length - 1 - headingSteps)]!, "behind");

  const starts = crossings(points, pointsXy, pauses, startLine, thresholds.lineHalfWidthM);
  const finishes = crossings(points, pointsXy, pauses, finishLine, thresholds.lineHalfWidthM);
  const efforts: MatchedEffort[] = [];
  let resumeAfterMs = Number.NEGATIVE_INFINITY;
  for (const start of starts) {
    if (start.atMs <= resumeAfterMs) {
      continue;
    }
    const finish = finishes.find((candidate) => candidate.atMs > start.atMs);
    if (!finish) {
      break;
    }
    const portion = [start.point, ...points.slice(start.index + 1, finish.index + 1), finish.point];
    if (hasGap(points, pauses, start.index, finish.index + 1, thresholds)) {
      continue;
    }
    const portionXy = resampleAlongTrack(portion, thresholds.resampleStepM).map(frame);
    if (
      coverage(segmentXy, portionXy, thresholds.coverageToleranceM) < thresholds.minCoverage ||
      !frechetWithin(portionXy, segmentXy, thresholds.maxFrechetM)
    ) {
      continue;
    }
    const first = points[0]!;
    const last = points.at(-1)!;
    efforts.push({
      startIndex: start.index,
      endIndex: finish.index + 1,
      startedAtMs: Math.round(start.atMs),
      endedAtMs: Math.round(finish.atMs),
      elapsedTimeS: Math.round((finish.atMs - start.atMs) / 1000),
      minDistanceToActivityStartM: Math.min(...portion.map((point) => haversineDistanceM(point, first))),
      minDistanceToActivityEndM: Math.min(...portion.map((point) => haversineDistanceM(point, last))),
    });
    resumeAfterMs = finish.atMs;
  }
  return efforts;
}

/**
 * Duplicate test of a new Segment (ADR-039 §5): each path, ridden as a trace, matches the
 * other. A shorter Segment inside a longer one is not a duplicate; the same road the other way
 * neither.
 */
export function isSameSegment(a: LonLat[], b: LonLat[]): boolean {
  return matchSegment(pathAsTrace(a), b).length > 0 && matchSegment(pathAsTrace(b), a).length > 0;
}

/**
 * A path as a trace, one point per second every resampling step, extended a little before its
 * start and after its finish so that it crosses its own lines.
 */
function pathAsTrace(path: LonLat[]): MatchingTrace {
  const resampled = resampleSegmentPath(path);
  if (resampled.length < 2) {
    return { points: [], pauses: [] };
  }
  const extendM = SEGMENT_MATCHING_THRESHOLDS.lineHalfWidthM;
  const beyond = (from: LonLat, towards: LonLat): LonLat => {
    const legM = haversineDistanceM(from, towards) || 1;
    const f = -extendM / legM;
    return { lat: from.lat + (towards.lat - from.lat) * f, lon: from.lon + (towards.lon - from.lon) * f };
  };
  const extended = [
    beyond(resampled[0]!, resampled[1]!),
    ...resampled,
    beyond(resampled.at(-1)!, resampled.at(-2)!),
  ];
  return { points: extended.map((point, i) => ({ ...point, timestampMs: i * 1000 })), pauses: [] };
}

type Xy = { x: number; y: number };

/** Equirectangular projection in meters centred on `origin`: exact enough at Segment scale. */
function localFrame(origin: LonLat): (point: LonLat) => Xy {
  const mPerDegLat = (6_371_000 * Math.PI) / 180;
  const mPerDegLon = mPerDegLat * Math.cos((origin.lat * Math.PI) / 180);
  return (point) => ({ x: (point.lon - origin.lon) * mPerDegLon, y: (point.lat - origin.lat) * mPerDegLat });
}

/** A virtual line through `at`, perpendicular to the Segment, crossed when moving along `heading`. */
interface Gate {
  at: Xy;
  heading: Xy;
}

function gate(at: Xy, other: Xy, side: "ahead" | "behind"): Gate {
  const dx = side === "ahead" ? other.x - at.x : at.x - other.x;
  const dy = side === "ahead" ? other.y - at.y : at.y - other.y;
  const norm = Math.hypot(dx, dy) || 1;
  return { at, heading: { x: dx / norm, y: dy / norm } };
}

interface Crossing {
  /** Index of the point just before the crossing. */
  index: number;
  atMs: number;
  point: LonLat;
}

/** Legs that cross `line` in its direction, within `halfWidthM` of its centre, outside Pauses. */
function crossings(
  points: MatchingPoint[],
  pointsXy: Xy[],
  pauses: MatchingPause[],
  line: Gate,
  halfWidthM: number,
): Crossing[] {
  const along = (p: Xy) => (p.x - line.at.x) * line.heading.x + (p.y - line.at.y) * line.heading.y;
  const across = (p: Xy) => (p.x - line.at.x) * line.heading.y - (p.y - line.at.y) * line.heading.x;
  const found: Crossing[] = [];
  for (let i = 0; i + 1 < points.length; i++) {
    const before = along(pointsXy[i]!);
    const after = along(pointsXy[i + 1]!);
    if (!(before < 0 && after >= 0) || straddlesPause(points[i]!, points[i + 1]!, pauses)) {
      continue;
    }
    const f = -before / (after - before);
    const a = pointsXy[i]!;
    const b = pointsXy[i + 1]!;
    if (Math.abs(across({ x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f })) > halfWidthM) {
      continue;
    }
    const p = points[i]!;
    const q = points[i + 1]!;
    found.push({
      index: i,
      atMs: p.timestampMs + (q.timestampMs - p.timestampMs) * f,
      point: { lat: p.lat + (q.lat - p.lat) * f, lon: p.lon + (q.lon - p.lon) * f },
    });
  }
  return found;
}

function straddlesPause(prev: MatchingPoint, curr: MatchingPoint, pauses: MatchingPause[]): boolean {
  return pauses.some((pause) => prev.timestampMs <= pause.startMs && curr.timestampMs >= pause.endMs);
}

/** A leg longer than the gap threshold, or a move during a Pause, between `from` and `to`. */
function hasGap(
  points: MatchingPoint[],
  pauses: MatchingPause[],
  from: number,
  to: number,
  thresholds: SegmentMatchingThresholds,
): boolean {
  for (let i = from; i < to; i++) {
    const legM = haversineDistanceM(points[i]!, points[i + 1]!);
    const limitM = straddlesPause(points[i]!, points[i + 1]!, pauses) ? thresholds.maxPauseMoveM : thresholds.maxGapM;
    if (legM > limitM) {
      return true;
    }
  }
  return false;
}

/** Share of the Segment's points within `toleranceM` of a point of the resampled portion. */
function coverage(segment: Xy[], portion: Xy[], toleranceM: number): number {
  const tolerance2 = toleranceM * toleranceM;
  let covered = 0;
  for (const s of segment) {
    if (portion.some((p) => (p.x - s.x) ** 2 + (p.y - s.y) ** 2 <= tolerance2)) {
      covered++;
    }
  }
  return covered / segment.length;
}

/**
 * Decision version of the discrete Fréchet distance (Eiter & Mannila 1994): whether a coupling
 * of `a` and `b` keeps every pair within `maxM`, in O(|a|·|b|) time and O(|b|) memory.
 */
function frechetWithin(a: Xy[], b: Xy[], maxM: number): boolean {
  const max2 = maxM * maxM;
  const near = (p: Xy, q: Xy) => (p.x - q.x) ** 2 + (p.y - q.y) ** 2 <= max2;
  let previous = new Array<boolean>(b.length).fill(false);
  let current = new Array<boolean>(b.length).fill(false);
  for (let i = 0; i < a.length; i++) {
    let any = false;
    for (let j = 0; j < b.length; j++) {
      const reachable =
        i === 0 && j === 0 ? true : (i > 0 && previous[j]!) || (j > 0 && current[j - 1]!) || (i > 0 && j > 0 && previous[j - 1]!);
      current[j] = reachable && near(a[i]!, b[j]!);
      any ||= current[j]!;
    }
    if (!any) {
      return false;
    }
    [previous, current] = [current, previous];
  }
  return previous[b.length - 1]!;
}
