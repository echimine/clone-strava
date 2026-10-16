import { randomUUID } from "node:crypto";
import { gzipSync } from "node:zlib";
import { getQueueToken } from "@nestjs/bullmq";
import { EventEmitter2 } from "@nestjs/event-emitter";
import type { Queue } from "bullmq";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import {
  ACTIVITIES_QUEUE_NAME,
  ACTIVITY_UPDATED_EVENT,
  TRACE_SCHEMA_VERSION,
  activityTraceKey,
  reprocessActivityJobId,
  type ActivityUpdatedEvent,
} from "@repo/contracts";
import { ActivitiesService, type ActivityDetailRecord } from "@repo/core/activities";
import { bootstrapTestWorkerApp, waitFor, type TestWorkerApp } from "../../testing/test-worker-app.js";

const M_PER_DEG_LAT = 111_195;
const START_LAT = 48.85;
const START_LON = 2.35;
const M_PER_DEG_LON = M_PER_DEG_LAT * Math.cos((START_LAT * Math.PI) / 180);

/**
 * Gzipped trace of a 22-minute outing, one point per minute: 20 legs of 300 m north (5 m/s)
 * with, after the 10th, a 1 km out-and-back spike east at ~16.7 m/s. As a run (12 m/s
 * plausible) the spike is a GPS jump: 6 km. As a ride (35 m/s) it counts: 8 km.
 */
function outingWithFastSpike(start: Date): Uint8Array {
  const north = (legs: number) => START_LAT + (legs * 300) / M_PER_DEG_LAT;
  const positions: Array<{ lat: number; lon: number }> = [];
  for (let leg = 0; leg <= 10; leg++) positions.push({ lat: north(leg), lon: START_LON });
  positions.push({ lat: north(10), lon: START_LON + 1000 / M_PER_DEG_LON });
  positions.push({ lat: north(10), lon: START_LON });
  for (let leg = 11; leg <= 20; leg++) positions.push({ lat: north(leg), lon: START_LON });
  return gzipSync(
    JSON.stringify({
      schemaVersion: TRACE_SCHEMA_VERSION,
      points: positions.map((position, minute) => ({
        timestampMs: start.getTime() + minute * 60_000,
        ...position,
        elevationM: 35,
        horizontalAccuracyM: 5,
      })),
      pauses: [],
    }),
  );
}

/**
 * Silent reprocessing after a sport change (ADR-033 §5) on real Postgres and Redis: the
 * `PATCH` use case enqueues `reprocess-activity`, the real processor recomputes the official
 * values for the new sport while the Activity stays `processed`.
 */
describe("reprocess-activity after a sport change (integration)", () => {
  let ctx: TestWorkerApp;
  let activities: ActivitiesService;
  let userId: string;

  beforeAll(async () => {
    ctx = await bootstrapTestWorkerApp();
    activities = ctx.app.get(ActivitiesService);
    userId = randomUUID();
    await ctx.db.$client.query('insert into "user" (id, name, email) values ($1, $2, $3)', [
      userId,
      "Reprocess test",
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

  function activitiesQueue(): Queue {
    return ctx.app.get<Queue>(getQueueToken(ACTIVITIES_QUEUE_NAME));
  }

  /** Records, uploads and processes a run with a fast spike; returns its processed detail. */
  async function processedRun(): Promise<ActivityDetailRecord> {
    const id = randomUUID();
    const start = new Date(Date.now() - 3 * 3_600_000);
    await activities.create(userId, {
      id,
      sportTypeCode: "run",
      title: "Sortie mal classée",
      startedAt: start.toISOString(),
      endedAt: new Date(start.getTime() + 22 * 60_000).toISOString(),
      visibility: "public",
      isManual: false,
    });
    ctx.storage.objects.set(activityTraceKey(userId, id), outingWithFastSpike(start));
    await activities.complete(userId, id);
    return waitFor(async () => {
      const detail = await activities.getDetail(userId, id);
      return detail.processingStatus === "processed" ? detail : undefined;
    });
  }

  it("recomputes distance and speeds for the new sport, staying processed throughout", async () => {
    const asRun = await processedRun();
    expect(asRun.stats?.distanceM).toBeCloseTo(6000, -2);
    expect(asRun.stats?.maxSpeedMs).toBeLessThan(12);

    await activities.update(userId, asRun.id, { sportTypeCode: "ride" });

    const asRide = await waitFor(async () => {
      const detail = await activities.getDetail(userId, asRun.id);
      // Never `processing` (nor anything else) while the job runs (ADR-033 §5).
      expect(detail.processingStatus).toBe("processed");
      return detail.stats?.distanceM !== asRun.stats?.distanceM ? detail : undefined;
    });
    expect(asRide.sportTypeCode).toBe("ride");
    expect(asRide.stats?.distanceM).toBeCloseTo(8000, -2);
    expect(asRide.stats?.maxSpeedMs).toBeCloseTo(1000 / 60, 0);
    expect(asRide.stats?.avgSpeedMs).toBeGreaterThan(asRun.stats!.avgSpeedMs!);
    expect(asRide.processingStatus).toBe("processed");
  }, 30_000);

  it("emits activities.activity.updated [stats] once the new values are committed", async () => {
    const asRun = await processedRun();
    const seen: Array<{ changedFields: string[]; distanceM: number | null | undefined }> = [];
    const listener = async (event: ActivityUpdatedEvent) => {
      if (event.activityId !== asRun.id) return;
      // What a listener reads when the event arrives: committed values only (ADR-021 §3).
      const detail = await activities.getDetail(userId, asRun.id);
      seen.push({ changedFields: event.changedFields, distanceM: detail.stats?.distanceM });
    };
    const emitter = ctx.app.get(EventEmitter2);
    emitter.on(ACTIVITY_UPDATED_EVENT, listener);
    try {
      await activities.update(userId, asRun.id, { sportTypeCode: "ride" });
      const statsEvent = await waitFor(async () => seen.find((e) => e.changedFields.includes("stats")));
      expect(statsEvent.changedFields).toEqual(["stats"]);
      expect(statsEvent.distanceM).toBeCloseTo(8000, -2);
    } finally {
      emitter.off(ACTIVITY_UPDATED_EVENT, listener);
    }

    // Forwarded to the author's devices like any edit (ADR-033 §8).
    const forwarded = await waitFor(async () =>
      ctx.realtimeMessages.find(
        (message) =>
          message.envelope.t === "activity.updated" &&
          message.envelope.data.activityId === asRun.id &&
          JSON.stringify(message.envelope.data.changedFields) === JSON.stringify(["stats"]),
      ),
    );
    expect(forwarded.topics).toContain(`user:${userId}`);
  }, 30_000);

  it("leaves the values alone when they were computed for the current sport", async () => {
    const asRun = await processedRun();
    // A marker the job would overwrite if it recomputed anything.
    await ctx.db.$client.query(
      "update activities.activity_stats set distance_m = 12345 where activity_id = $1",
      [asRun.id],
    );
    const updates: ActivityUpdatedEvent[] = [];
    const listener = (event: ActivityUpdatedEvent) => void updates.push(event);
    const emitter = ctx.app.get(EventEmitter2);
    emitter.on(ACTIVITY_UPDATED_EVENT, listener);
    try {
      await activities.reprocess({ activityId: asRun.id, userId });
    } finally {
      emitter.off(ACTIVITY_UPDATED_EVENT, listener);
    }

    const detail = await activities.getDetail(userId, asRun.id);
    expect(detail.stats?.distanceM).toBe(12345);
    expect(detail.processingStatus).toBe("processed");
    expect(updates.filter((event) => event.activityId === asRun.id)).toEqual([]);
  }, 30_000);

  it("keeps the old values and the processed status when the reprocessing fails", async () => {
    const asRun = await processedRun();
    // An unusable trace: a permanent failure, given up at once.
    ctx.storage.objects.set(activityTraceKey(userId, asRun.id), new TextEncoder().encode("not gzip"));

    const edited = await activities.update(userId, asRun.id, { sportTypeCode: "ride" });

    const jobId = reprocessActivityJobId(asRun.id, edited.updatedAt);
    await waitFor(async () => ((await activitiesQueue().getJobState(jobId)) === "failed" ? true : undefined));
    expect((await activitiesQueue().getJob(jobId))?.failedReason).toContain("invalid_trace");
    const detail = await activities.getDetail(userId, asRun.id);
    expect(detail.processingStatus).toBe("processed");
    expect(detail.processingError).toBeNull();
    expect(detail.sportTypeCode).toBe("ride");
    expect(detail.stats).toEqual(asRun.stats);
  }, 30_000);

  it("is enqueued by the reconciliation when the values lag behind the sport", async () => {
    const asRun = await processedRun();
    // A sport change committed whose enqueue was lost (a crash right after the commit).
    await ctx.db.$client.query(
      "update activities.activity set sport_type_code = 'ride' where id = $1",
      [asRun.id],
    );

    expect(await activities.reconcileStuck()).toBeGreaterThanOrEqual(1);

    // The job id of the last edit, the one the `PATCH` would have used.
    const jobId = reprocessActivityJobId(asRun.id, asRun.updatedAt);
    expect(await activitiesQueue().getJob(jobId)).toBeDefined();
    const asRide = await waitFor(async () => {
      const detail = await activities.getDetail(userId, asRun.id);
      return detail.stats?.distanceM !== asRun.stats?.distanceM ? detail : undefined;
    });
    expect(asRide.stats?.distanceM).toBeCloseTo(8000, -2);
    expect(asRide.processingStatus).toBe("processed");

    // Up to date now: even with its finished job gone, the next sweep enqueues nothing for it.
    await waitFor(async () => ((await activitiesQueue().getJobState(jobId)) === "completed" ? true : undefined));
    await activitiesQueue().remove(jobId);
    await activities.reconcileStuck();
    expect(await activitiesQueue().getJob(jobId)).toBeUndefined();
  }, 30_000);
});
