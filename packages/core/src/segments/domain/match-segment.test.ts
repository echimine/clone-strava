import { describe, expect, it } from "vitest";
import { isSameSegment, matchSegment, type MatchingTrace } from "./match-segment.js";

/**
 * Fixtures built in a local frame in meters (x east, y north) around 45° N, 5° E: their times
 * come from their construction (distance / speed), never from the code under test.
 */
const ORIGIN = { lat: 45, lon: 5 };
const M_PER_DEG_LAT = (6_371_000 * Math.PI) / 180;
const M_PER_DEG_LON = M_PER_DEG_LAT * Math.cos((ORIGIN.lat * Math.PI) / 180);
const T0 = Date.UTC(2026, 10, 5, 8);

type Xy = [x: number, y: number];

function toLonLat([x, y]: Xy) {
  return { lat: ORIGIN.lat + y / M_PER_DEG_LAT, lon: ORIGIN.lon + x / M_PER_DEG_LON };
}

/** A Segment path through the waypoints. */
function path(...waypoints: Xy[]) {
  return waypoints.map(toLonLat);
}

/**
 * A trace along the waypoints at `speedMs`, one point every `everyS` seconds, starting at
 * `startMs`; `noise` shifts each point (meters).
 */
function traceAlong(
  waypoints: Xy[],
  { speedMs = 5, everyS = 1, startMs = T0, noise = (_i: number): Xy => [0, 0] } = {},
): MatchingTrace {
  const lengthM = polylineLength(waypoints);
  const points: MatchingTrace["points"] = [];
  for (let i = 0; i * speedMs * everyS <= lengthM + 1e-9; i++) {
    const [x, y] = pointAtDistance(waypoints, i * speedMs * everyS);
    const [nx, ny] = noise(i);
    points.push({ ...toLonLat([x + nx, y + ny]), timestampMs: startMs + i * everyS * 1000 });
  }
  return { points, pauses: [] };
}

function polylineLength(waypoints: Xy[]): number {
  let total = 0;
  for (let i = 1; i < waypoints.length; i++) {
    total += Math.hypot(waypoints[i]![0] - waypoints[i - 1]![0], waypoints[i]![1] - waypoints[i - 1]![1]);
  }
  return total;
}

function pointAtDistance(waypoints: Xy[], distanceM: number): Xy {
  let left = distanceM;
  for (let i = 1; i < waypoints.length; i++) {
    const [ax, ay] = waypoints[i - 1]!;
    const [bx, by] = waypoints[i]!;
    const legM = Math.hypot(bx - ax, by - ay);
    if (left <= legM) {
      return [ax + ((bx - ax) * left) / legM, ay + ((by - ay) * left) / legM];
    }
    left -= legM;
  }
  return waypoints.at(-1)!;
}

/** A 1 km straight Segment heading east. */
const EAST_KM = path([0, 0], [1000, 0]);

describe("matchSegment", () => {
  it("times a single pass along the Segment, from crossing to crossing", () => {
    // From 200 m before the start to 200 m after the finish at 5 m/s: the start line is crossed
    // 40 s in, the finish line 240 s in.
    const trace = traceAlong([
      [-200, 0],
      [1200, 0],
    ]);

    const efforts = matchSegment(trace, EAST_KM);

    expect(efforts).toHaveLength(1);
    expect(efforts[0]).toMatchObject({ startedAtMs: T0 + 40_000, elapsedTimeS: 200 });
    expect(efforts[0]!.startIndex).toBeLessThanOrEqual(40);
    expect(efforts[0]!.endIndex).toBeGreaterThanOrEqual(240);
  });

  it("finds nothing on the Segment ridden the wrong way", () => {
    const trace = traceAlong([
      [1200, 0],
      [-200, 0],
    ]);

    expect(matchSegment(trace, EAST_KM)).toEqual([]);
  });

  it("finds one Effort on an out-and-back over the Segment: the way out only", () => {
    // Out at 5 m/s from -200 m to 1,200 m (280 s), then back.
    const trace = traceAlong([
      [-200, 0],
      [1200, 0],
      [-200, 0],
    ]);

    const efforts = matchSegment(trace, EAST_KM);

    expect(efforts).toHaveLength(1);
    expect(efforts[0]).toMatchObject({ startedAtMs: T0 + 40_000, elapsedTimeS: 200 });
  });

  it("finds three Efforts on a loop ridden three times", () => {
    // A 3,200 m rectangular circuit whose southern side holds the Segment; 640 s per lap at
    // 5 m/s, the start line crossed 40 s into each lap.
    const lap: Xy[] = [
      [-200, 0],
      [1200, 0],
      [1200, 200],
      [-200, 200],
      [-200, 0],
    ];
    const trace = traceAlong([...lap, ...lap.slice(1), ...lap.slice(1)]);

    const efforts = matchSegment(trace, EAST_KM);

    expect(efforts.map((effort) => effort.startedAtMs)).toEqual([T0 + 40_000, T0 + 680_000, T0 + 1_320_000]);
    expect(efforts.map((effort) => effort.elapsedTimeS)).toEqual([200, 200, 200]);
  });

  it("refuses a shortcut that crosses both lines but cuts the corner", () => {
    // An L-shaped Segment, 500 m east then 500 m north; the trace goes straight from its start
    // to past its finish.
    const corner = path([0, 0], [500, 0], [500, 500]);
    const trace = traceAlong([
      [-50, -50],
      [530, 530],
    ]);

    expect(matchSegment(trace, corner)).toEqual([]);
  });

  it("still finds the Effort on a noisy GPS trace", () => {
    // ±8 m of deterministic noise across and along the line.
    const trace = traceAlong(
      [
        [-200, 0],
        [1200, 0],
      ],
      { noise: (i) => [Math.sin(i * 1.7) * 8, Math.cos(i * 2.3) * 8] },
    );

    const efforts = matchSegment(trace, EAST_KM);

    expect(efforts).toHaveLength(1);
    expect(Math.abs(efforts[0]!.elapsedTimeS - 200)).toBeLessThanOrEqual(4);
  });

  it("interpolates the crossings of a sparse import, one point every 7 s", () => {
    // 35 m between points: the lines fall between two points, the time stays 200 s.
    const trace = traceAlong(
      [
        [-200, 0],
        [1200, 0],
      ],
      { everyS: 7 },
    );

    const efforts = matchSegment(trace, EAST_KM);

    expect(efforts).toHaveLength(1);
    expect(efforts[0]).toMatchObject({ startedAtMs: T0 + 40_000, elapsedTimeS: 200 });
  });

  it("refuses a portion with a gap in the data", () => {
    const trace = traceAlong([
      [-200, 0],
      [1200, 0],
    ]);
    // 300 m without a point in the middle of the Segment.
    trace.points = trace.points.filter((_point, i) => i < 120 || i > 180);

    expect(matchSegment(trace, EAST_KM)).toEqual([]);
  });

  it("counts a Pause in the elapsed time when the athlete did not move", () => {
    const trace = traceAlong([
      [-200, 0],
      [1200, 0],
    ]);
    // A 60 s stop 500 m in (point 140): every later point is shifted by 60 s.
    const pauseStart = trace.points[140]!.timestampMs;
    trace.points = trace.points.map((point, i) => (i > 140 ? { ...point, timestampMs: point.timestampMs + 60_000 } : point));
    trace.pauses = [{ startMs: pauseStart, endMs: pauseStart + 61_000 }];

    const efforts = matchSegment(trace, EAST_KM);

    expect(efforts).toHaveLength(1);
    expect(efforts[0]!.elapsedTimeS).toBe(260);
  });

  it("refuses a portion where the athlete moved during a Pause", () => {
    const trace = traceAlong([
      [-200, 0],
      [1200, 0],
    ]);
    // A Pause between points 100 and 140: 200 m covered while paused.
    trace.pauses = [{ startMs: trace.points[100]!.timestampMs, endMs: trace.points[140]!.timestampMs }];
    trace.points = trace.points.filter((_point, i) => i <= 100 || i >= 140);

    expect(matchSegment(trace, EAST_KM)).toEqual([]);
  });

  it("measures how close the Effort comes to the Activity's first and last points", () => {
    // Starts 150 m before the Segment, ends 400 m after it.
    const trace = traceAlong([
      [-150, 0],
      [1400, 0],
    ]);

    const [effort] = matchSegment(trace, EAST_KM);

    expect(effort!.minDistanceToActivityStartM).toBeCloseTo(150, 0);
    expect(effort!.minDistanceToActivityEndM).toBeCloseTo(400, 0);
  });

  it("times the real pass after a false start", () => {
    // Crosses the start line, turns back 100 m in, then goes again from 200 m before.
    const trace = traceAlong([
      [-200, 0],
      [100, 0],
      [-200, 0],
      [1200, 0],
    ]);

    const efforts = matchSegment(trace, EAST_KM);

    // 300 + 300 m before the second approach, then 200 m to the line: 160 s in.
    expect(efforts).toHaveLength(1);
    expect(efforts[0]).toMatchObject({ startedAtMs: T0 + 160_000, elapsedTimeS: 200 });
  });
});

describe("isSameSegment (both-ways duplicate test, ADR-039 §5)", () => {
  it("holds for the same path drawn with other points", () => {
    expect(isSameSegment(EAST_KM, path([0, 3], [400, -4], [1000, 2]))).toBe(true);
  });

  it("does not hold for a shorter Segment inside a longer one", () => {
    expect(isSameSegment(EAST_KM, path([200, 0], [800, 0]))).toBe(false);
  });

  it("does not hold for the same road the other way", () => {
    expect(isSameSegment(EAST_KM, path([1000, 0], [0, 0]))).toBe(false);
  });
});
