import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { traceSchema } from "@repo/contracts";
import { describe, expect, it } from "vitest";
import { cleanTrace, MAX_TRACE_ACCURACY_M, maxPlausibleSpeedMs } from "./clean-trace.js";
import { computeMetrics } from "./compute-metrics.js";

/** Shared timestamped traces, also replayed by the Swift tests (ADR-031 §5). */
const TRACES_DIR = join(__dirname, "..", "..", "..", "..", "contracts", "fixtures", "traces");

interface SharedTrace {
  sportTypeCode: string;
  expected: { distanceM: number; movingTimeS: number; elapsedTimeS: number };
  trace: unknown;
}

const files = readdirSync(TRACES_DIR)
  .filter((file) => file.endsWith(".json"))
  .sort();

describe("shared test traces", () => {
  it("cover a trace without Pause, a move during a Pause and imprecise points", () => {
    expect(files).toEqual(
      expect.arrayContaining([
        "run-no-pause.json",
        "run-train-during-pause.json",
        "walk-imprecise-points.json",
      ]),
    );
  });

  it.each(files)("%s gives its expected official values", (file) => {
    const shared = JSON.parse(readFileSync(join(TRACES_DIR, file), "utf8")) as SharedTrace;
    const trace = traceSchema.parse(shared.trace);

    const points = cleanTrace(trace.points, {
      maxAccuracyM: MAX_TRACE_ACCURACY_M,
      maxSpeedMs: maxPlausibleSpeedMs(shared.sportTypeCode),
      pauses: trace.pauses,
    });
    const metrics = computeMetrics(points, { pauses: trace.pauses });

    expect(metrics.distanceM).toBeCloseTo(shared.expected.distanceM, 1);
    expect(metrics.movingTimeS).toBe(shared.expected.movingTimeS);
    expect(metrics.elapsedTimeS).toBe(shared.expected.elapsedTimeS);
  });
});
