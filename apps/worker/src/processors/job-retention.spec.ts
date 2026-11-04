import { randomUUID } from "node:crypto";
import { gzipSync } from "node:zlib";
import { getQueueToken } from "@nestjs/bullmq";
import type { Queue } from "bullmq";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import {
  ACTIVITIES_QUEUE_NAME,
  BUCKET_SWEEP_JOB_NAME,
  BUCKET_SWEEP_QUEUE_NAME,
  SEGMENTS_QUEUE_NAME,
  TRACE_SCHEMA_VERSION,
  activityTraceKey,
  matchSegmentsJobId,
} from "@repo/contracts";
import { ActivitiesService } from "@repo/core/activities";
import { bootstrapTestWorkerApp, waitFor, type TestWorkerApp } from "../testing/test-worker-app.js";

const DAY_S = 24 * 3600;
/** ADR-038 §14 (amends ADR-011): completed jobs 7 days / 1000, failed jobs 30 days / 5000. */
const RETENTION = {
  removeOnComplete: { age: 7 * DAY_S, count: 1000 },
  removeOnFail: { age: 30 * DAY_S, count: 5000 },
};

/**
 * Bounded retention everywhere (ADR-038 §14): the jobs the worker chains and the templates of
 * its two schedulers never pile up in Redis.
 */
describe("job retention (integration)", () => {
  let ctx: TestWorkerApp;
  let userId: string;

  const queue = (name: string) => ctx.app.get<Queue>(getQueueToken(name));

  beforeAll(async () => {
    ctx = await bootstrapTestWorkerApp();
    userId = randomUUID();
    await ctx.db.$client.query('insert into "user" (id, name, email) values ($1, $2, $3)', [
      userId,
      "Retention test",
      `${userId}@test.local`,
    ]);
  }, 30_000);

  afterAll(async () => {
    if (userId) {
      await ctx.db.$client.query('delete from "user" where id = $1', [userId]);
    }
    await ctx?.close();
  });

  it("chains match-segments with the default retry policy and retention", async () => {
    const activities = ctx.app.get(ActivitiesService);
    const id = randomUUID();
    const start = new Date(Date.now() - 2 * 3_600_000);
    await activities.create(userId, {
      id,
      sportTypeCode: "run",
      title: "Sortie",
      startedAt: start.toISOString(),
      endedAt: new Date(start.getTime() + 5 * 60_000).toISOString(),
      visibility: "public",
      isManual: false,
    });
    ctx.storage.objects.set(activityTraceKey(userId, id), recordedRun(start));
    await activities.complete(userId, id);

    const job = await waitFor(() => queue(SEGMENTS_QUEUE_NAME).getJob(matchSegmentsJobId(id)));

    expect(job.opts).toMatchObject({ attempts: 5, ...RETENTION });
  }, 30_000);

  it("gives the reconciliation's and the bucket sweep's templates the same retention", async () => {
    const [reconcile] = await queue(ACTIVITIES_QUEUE_NAME).getJobSchedulers();
    const [sweep] = await queue(BUCKET_SWEEP_QUEUE_NAME).getJobSchedulers();

    expect(reconcile).toMatchObject({ name: "reconcile-activities", template: { opts: RETENTION } });
    expect(sweep).toMatchObject({ name: BUCKET_SWEEP_JOB_NAME, template: { opts: RETENTION } });
  });
});

/** Gzipped trace v2 of a 5-minute run, one point per minute. */
function recordedRun(start: Date): Uint8Array {
  return gzipSync(
    JSON.stringify({
      schemaVersion: TRACE_SCHEMA_VERSION,
      points: [0, 1, 2, 3, 4, 5].map((minute, i) => ({
        timestampMs: start.getTime() + minute * 60_000,
        lat: 48.85 + i * 0.001,
        lon: 2.35,
        elevationM: 35,
        horizontalAccuracyM: 5,
      })),
      pauses: [],
    }),
  );
}
