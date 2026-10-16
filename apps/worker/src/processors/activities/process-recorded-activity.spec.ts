import { randomUUID } from "node:crypto";
import { gzipSync } from "node:zlib";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { TRACE_SCHEMA_VERSION, activityTraceKey } from "@repo/contracts";
import { ActivitiesService } from "@repo/core/activities";
import { bootstrapTestWorkerApp, waitFor, type TestWorkerApp } from "../../testing/test-worker-app.js";

/** Gzipped trace v2 of a 12-minute run with a 2-minute Pause, one point per minute, ~111 m apart. */
function recordedRun(start: Date): Uint8Array {
  const t = (minute: number) => start.getTime() + minute * 60_000;
  const minutes = [0, 1, 2, 3, 4, 5, 8, 9, 10, 11, 12];
  return gzipSync(
    JSON.stringify({
      schemaVersion: TRACE_SCHEMA_VERSION,
      points: minutes.map((minute, i) => ({
        timestampMs: t(minute),
        lat: 48.85 + i * 0.001,
        lon: 2.35,
        elevationM: 35,
        horizontalAccuracyM: 5,
      })),
      pauses: [{ startMs: t(5) + 30_000, endMs: t(8) - 30_000 }],
    }),
  );
}

/**
 * The whole recorded-activity journey (ADR-019, ADR-031 §13) on real
 * Postgres and Redis: create, upload the trace, `complete`; the real
 * `process-activity` processor computes the official values and the
 * activity shows up in its author's feed.
 */
describe("process-activity of a recorded activity (integration)", () => {
  let ctx: TestWorkerApp;
  let activities: ActivitiesService;
  let userId: string;

  beforeAll(async () => {
    ctx = await bootstrapTestWorkerApp();
    activities = ctx.app.get(ActivitiesService);
    userId = randomUUID();
    await ctx.db.$client.query('insert into "user" (id, name, email) values ($1, $2, $3)', [
      userId,
      "Recording test",
      `${userId}@test.local`,
    ]);
  }, 30_000);

  afterAll(async () => {
    if (userId) {
      // Cascades to the user's activities.
      await ctx.db.$client.query('delete from "user" where id = $1', [userId]);
    }
    await ctx?.close();
  });

  it("processes a recorded activity into its author's feed", async () => {
    const id = randomUUID();
    const start = new Date(Date.now() - 2 * 3_600_000);
    const created = await activities.create(userId, {
      id,
      sportTypeCode: "run",
      title: "Sortie enregistrée",
      startedAt: start.toISOString(),
      endedAt: new Date(start.getTime() + 12 * 60_000).toISOString(),
      visibility: "public",
      isManual: false,
      distanceM: 999_999,
    });
    expect(created.uploadUrl?.uploadUrl).toContain(activityTraceKey(userId, id));

    ctx.storage.objects.set(activityTraceKey(userId, id), recordedRun(start));
    await activities.complete(userId, id, "req-recorded");

    const detail = await waitFor(async () => {
      const own = await activities.getDetail(userId, id);
      return own.processingStatus === "processed" ? own : undefined;
    });
    // 10 legs of ~111.2 m; the leg across the Pause is skipped (ADR-031 §12): 9 legs remain.
    expect(detail.stats?.distanceM).toBeCloseTo(1000, -1);
    expect(detail.stats?.elapsedTimeS).toBe(720);
    expect(detail.stats?.movingTimeS).toBe(540);

    const feed = await activities.getFeedPage(userId, { limit: 20 });
    expect(feed.items.map((item) => item.id)).toContain(id);

    const types = await waitFor(async () => {
      const mine = ctx.realtimeMessages
        .filter((message) => message.topics.includes(`user:${userId}`))
        .map((message) => message.envelope.t);
      return mine.includes("activity.processed") ? mine : undefined;
    });
    expect(types).toContain("activity.processed");
  }, 30_000);
});
