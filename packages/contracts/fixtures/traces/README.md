# Shared test traces

Timestamped traces with their expected official values (ADR-031 §5, §12). They are
read by the TypeScript tests (`packages/core/src/activities/domain/shared-traces.test.ts`:
contract validation, `cleanTrace`, then `computeMetrics`) and are meant for the Swift tests too,
whose provisional distance must stay within **±1 %** of `expected.distanceM`.

## Format

```json
{
  "description": "what the trace exercises",
  "sportTypeCode": "run",
  "expected": { "distanceM": 1800, "movingTimeS": 600, "elapsedTimeS": 600 },
  "trace": { "schemaVersion": 2, "points": [...], "pauses": [...] }
}
```

`trace` is a trace v2 (`packages/contracts/src/activities/trace.ts`), exactly as stored in the
bucket. Cleanup uses the server rules: accuracy ≤ 50 m and the sport's plausible top speed.

## Traces

| File                          | What it covers                                                                      |
| ----------------------------- | ----------------------------------------------------------------------------------- |
| `run-no-pause.json`           | 600 legs of 3 m, no Pause                                                           |
| `run-train-during-pause.json` | 60 km by train during a 1 h Pause: neither distance nor moving time, but total time |
| `walk-imprecise-points.json`  | inaccurate fixes (> 50 m) and a GPS jump, all dropped by the cleanup                |
| `ride-long-loop.json`         | a 52 km ride, 1,040 legs of 50 m every 5 s: the long outing of the celebration      |

## Expected values

They come from the construction, not from the code under test: every leg is built on the
6,371 km sphere used by `@repo/geo` to measure exactly its trace's step along a meridian or a
parallel: 3 m for the runs, 1.5 m for the walk, 50 m for the ride. The distance is the number
of kept legs times the step. An ellipsoidal distance
(e.g. `CLLocation.distance(from:)`) differs by well under 1 %.

A new trace needs its expected values worked out the same way, independently of `computeMetrics`.
