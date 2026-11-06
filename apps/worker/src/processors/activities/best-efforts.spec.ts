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
  reprocessAnalysisJobId,
  type ActivityUpdatedEvent,
} from "@repo/contracts";
import { ACTIVITY_ANALYSIS_VERSION, ActivitiesService } from "@repo/core/activities";
import { NO_EXCLUSIONS } from "@repo/core/infrastructure";
import { bootstrapTestWorkerApp, waitFor, type TestWorkerApp } from "../../testing/test-worker-app.js";

/** Meters per degree of latitude on the sphere `haversineDistanceM` uses. */
const M_PER_DEG_LAT = (6_371_000 * Math.PI) / 180;
const DAY_MS = 86_400_000;

/** Gzipped trace of a steady 5.2 km straight line north at `speedMs`, one point every 10 s. */
function steadyTrace(start: Date, speedMs: number): Uint8Array {
  const stepM = speedMs * 10;
  const count = Math.round(5200 / stepM);
  return gzipSync(
    JSON.stringify({
      schemaVersion: TRACE_SCHEMA_VERSION,
      points: Array.from({ length: count + 1 }, (_, i) => ({
        timestampMs: start.getTime() + i * 10_000,
        lat: 48.85 + (i * stepM) / M_PER_DEG_LAT,
        lon: 2.35,
        elevationM: 35,
        horizontalAccuracyM: 5,
      })),
      pauses: [],
    }),
  );
}

/**
 * Best efforts and their Medals (ADR-039 §3, §8) on real Postgres and Redis: written by
 * `process-activity` and `reprocess-activity`, replayed in date order whenever the athlete's
 * history changes.
 */
describe("Best efforts (integration)", () => {
  let ctx: TestWorkerApp;
  let activities: ActivitiesService;
  const users: string[] = [];

  beforeAll(async () => {
    ctx = await bootstrapTestWorkerApp();
    activities = ctx.app.get(ActivitiesService);
  }, 30_000);

  afterAll(async () => {
    for (const userId of users) {
      // Cascades to the athlete's Activities and Best efforts.
      await ctx.db.$client.query('delete from "user" where id = $1', [userId]);
    }
    await ctx?.close();
  });

  async function newAthlete(): Promise<string> {
    const userId = randomUUID();
    users.push(userId);
    await ctx.db.$client.query('insert into "user" (id, name, email) values ($1, $2, $3)', [
      userId,
      "Best efforts test",
      `${userId}@test.local`,
    ]);
    return userId;
  }

  function activitiesQueue(): Queue {
    return ctx.app.get<Queue>(getQueueToken(ACTIVITIES_QUEUE_NAME));
  }

  /** Records and processes a steady 5.2 km run, `daysAgo` days ago; returns its id. */
  async function processedRun(userId: string, { daysAgo, speedMs }: { daysAgo: number; speedMs: number }) {
    const id = randomUUID();
    const start = new Date(Date.now() - daysAgo * DAY_MS);
    await activities.create(userId, {
      id,
      sportTypeCode: "run",
      title: "Course",
      startedAt: start.toISOString(),
      endedAt: new Date(start.getTime() + (5200 / speedMs) * 1000).toISOString(),
      visibility: daysAgo % 2 === 0 ? "public" : "private",
      isManual: false,
    });
    ctx.storage.objects.set(activityTraceKey(userId, id), steadyTrace(start, speedMs));
    await activities.complete(userId, id);
    await waitFor(async () => {
      const detail = await activities.getDetail(userId, id, NO_EXCLUSIONS);
      return detail.processingStatus === "processed" ? true : undefined;
    });
    return id;
  }

  /** `{ distanceM: medal }` of an Activity's Best efforts not removed. */
  async function medals(activityId: string) {
    const { bestEfforts } = await activities.getBestEffortResults(activityId);
    return Object.fromEntries(bestEfforts.map((effort) => [effort.distanceM, effort.medal]));
  }

  it("times every Record distance of a processed run, its first times all gold", async () => {
    const userId = await newAthlete();
    const id = await processedRun(userId, { daysAgo: 2, speedMs: 4 });

    const { bestEfforts: efforts } = await activities.getBestEffortResults(id);

    expect(efforts.map((effort) => [effort.distanceM, effort.elapsedTimeMs])).toEqual([
      [400, 100_000],
      [1000, 250_000],
      [2000, 500_000],
      [3000, 750_000],
      [5000, 1_250_000],
    ]);
    expect(efforts.every((effort) => effort.medal === "gold")).toBe(true);
  }, 30_000);

  it("replays the Medals in date order when an older Activity is processed later", async () => {
    const userId = await newAthlete();
    const first = await processedRun(userId, { daysAgo: 4, speedMs: 4 });
    const second = await processedRun(userId, { daysAgo: 2, speedMs: 3.5 });
    expect(await medals(second)).toMatchObject({ 5000: "silver" });

    // Imported afterwards, older and faster than both, whatever its visibility.
    const older = await processedRun(userId, { daysAgo: 9, speedMs: 5 });

    expect(await medals(older)).toMatchObject({ 400: "gold", 5000: "gold" });
    expect(await medals(first)).toMatchObject({ 400: "silver", 5000: "silver" });
    expect(await medals(second)).toMatchObject({ 400: "bronze", 5000: "bronze" });
  }, 30_000);

  it("moves the Best efforts to the new family when the sport changes, replaying both", async () => {
    const userId = await newAthlete();
    const fast = await processedRun(userId, { daysAgo: 4, speedMs: 5 });
    const slow = await processedRun(userId, { daysAgo: 2, speedMs: 4 });
    expect(await medals(slow)).toMatchObject({ 5000: "silver" });

    await activities.update(userId, fast, { sportTypeCode: "ride" });

    // A ride has no Record under 5 km: the run distances are gone once recomputed.
    const asRide = await waitFor(async () => {
      const { bestEfforts } = await activities.getBestEffortResults(fast);
      return bestEfforts.some((effort) => effort.distanceM === 400) ? undefined : bestEfforts;
    });
    expect(asRide.map((effort) => [effort.distanceM, effort.medal])).toEqual([[5000, "gold"]]);
    expect(await medals(slow)).toMatchObject({ 400: "gold", 5000: "gold" });
  }, 30_000);

  it("computes them when the analysis lags, keeping the place name, silently", async () => {
    const userId = await newAthlete();
    const id = await processedRun(userId, { daysAgo: 2, speedMs: 4 });
    // As processed before ADR-039: an analysis v1, no Best effort, a place name geocoded then.
    await ctx.db.$client.query("delete from activities.best_effort where activity_id = $1", [id]);
    await ctx.db.$client.query("update activities.activity_analysis set version = 1 where activity_id = $1", [id]);
    await ctx.db.$client.query(
      "update activities.activity_track set location_name = 'Paris, Paris' where activity_id = $1",
      [id],
    );

    const updates: ActivityUpdatedEvent[] = [];
    const listener = (event: ActivityUpdatedEvent) => void updates.push(event);
    ctx.app.get(EventEmitter2).on(ACTIVITY_UPDATED_EVENT, listener);
    try {
      await activities.reconcileStuck();
      const jobId = reprocessAnalysisJobId(id, ACTIVITY_ANALYSIS_VERSION);
      await waitFor(async () => ((await activitiesQueue().getJobState(jobId)) === "completed" ? true : undefined));
    } finally {
      ctx.app.get(EventEmitter2).off(ACTIVITY_UPDATED_EVENT, listener);
    }

    expect(await medals(id)).toEqual({ 400: "gold", 1000: "gold", 2000: "gold", 3000: "gold", 5000: "gold" });
    expect((await activities.getDetail(userId, id, NO_EXCLUSIONS)).locationName).toBe("Paris, Paris");
    expect(updates.filter((event) => event.activityId === id)).toEqual([]);
  }, 30_000);

  it("removes a Best effort for good: the next one takes the Medal, a recomputation keeps it out", async () => {
    const userId = await newAthlete();
    const fast = await processedRun(userId, { daysAgo: 4, speedMs: 5 });
    const slow = await processedRun(userId, { daysAgo: 2, speedMs: 4 });

    await activities.removeBestEffort(userId, fast, 5000);

    expect(await medals(fast)).toEqual({ 400: "gold", 1000: "gold", 2000: "gold", 3000: "gold" });
    expect(await medals(slow)).toMatchObject({ 400: "silver", 5000: "gold" });

    // The whole history is recomputed (a new analysis version): the row stays removed.
    await ctx.db.$client.query("update activities.activity_analysis set version = 1 where activity_id = $1", [fast]);
    await activities.reprocess({ activityId: fast, userId });
    expect(await medals(fast)).toEqual({ 400: "gold", 1000: "gold", 2000: "gold", 3000: "gold" });
    expect(await medals(slow)).toMatchObject({ 5000: "gold" });
  }, 30_000);

  it("refuses to remove the Best effort of another athlete, or one that does not exist", async () => {
    const userId = await newAthlete();
    const other = await newAthlete();
    const id = await processedRun(userId, { daysAgo: 2, speedMs: 4 });

    await expect(activities.removeBestEffort(other, id, 5000)).rejects.toMatchObject({ status: 404 });
    await expect(activities.removeBestEffort(userId, id, 10000)).rejects.toMatchObject({ status: 404 });
    expect(await medals(id)).toMatchObject({ 5000: "gold" });
  }, 30_000);

  it("replays the Medals of the athlete's distances when an Activity is deleted", async () => {
    const userId = await newAthlete();
    const fast = await processedRun(userId, { daysAgo: 4, speedMs: 5 });
    const slow = await processedRun(userId, { daysAgo: 2, speedMs: 4 });
    expect(await medals(slow)).toMatchObject({ 5000: "silver" });

    await activities.delete(userId, fast);

    expect((await activities.getBestEffortResults(fast)).bestEfforts).toEqual([]);
    expect(await medals(slow)).toEqual({ 400: "gold", 1000: "gold", 2000: "gold", 3000: "gold", 5000: "gold" });
  }, 30_000);
});
