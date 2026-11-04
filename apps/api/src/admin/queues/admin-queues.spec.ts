import { randomUUID } from "node:crypto";
import { getQueueToken } from "@nestjs/bullmq";
import { Worker, type Job, type Queue } from "bullmq";
import { Redis } from "ioredis";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import {
  ADMIN_QUEUE_NAMES,
  type AdminQueueJobDetail,
  type AdminQueueJobListResponse,
  type AdminQueueListResponse,
  type AdminQueueRetryFailedResponse,
} from "@repo/contracts";
import { TEST_REDIS_URL } from "../../auth/test-auth-app.js";
import { bootstrapAdminTestApp, type AdminTestApp } from "../../testing/admin-test-app.js";
import { AdminQueuesController } from "./admin-queues.controller.js";
import { AdminQueuesModule } from "./admin-queues.module.js";

/**
 * The "Files" tab of the Jobs screen (ADR-038 §14): the whitelisted queues read and driven
 * through `/v1/admin/queues/*`, over real HTTP and Redis. Failures come from a real BullMQ
 * worker whose processor throws.
 */
describe("/v1/admin/queues (integration)", { timeout: 20_000 }, () => {
  let t: AdminTestApp;
  let admin: string;
  let athleteId: string;
  const workers: Worker[] = [];
  const connections: Redis[] = [];

  const queue = (name: string) => t.app.get<Queue>(getQueueToken(name));

  /** Runs `name`'s jobs on a worker that fails each of them once and for all. */
  function failEveryJob(name: string): void {
    const connection = new Redis(TEST_REDIS_URL, { maxRetriesPerRequest: null });
    connections.push(connection);
    workers.push(
      new Worker(
        name,
        async (job: Job) => {
          throw new Error(`boom ${job.name}`);
        },
        { connection, prefix: queue(name).opts.prefix },
      ),
    );
  }

  async function failedJob(queueName: string, jobName: string, data: Record<string, unknown>): Promise<Job> {
    const job = await queue(queueName).add(jobName, data, { attempts: 1, jobId: `${jobName}-${randomUUID()}` });
    for (let i = 0; i < 100 && (await job.getState()) !== "failed"; i++) {
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
    expect(await job.getState()).toBe("failed");
    return job;
  }

  async function journal(action: string) {
    return t.sql<{ target_type: string; target_id: string | null; reason: string | null; details: unknown }>(
      "select * from audit.admin_audit_entry where action = $1 and actor_id = $2",
      [action, admin],
    );
  }

  const errorCode = async (response: Response) =>
    ((await response.json()) as { error: { code: string } }).error.code;

  beforeAll(async () => {
    t = await bootstrapAdminTestApp({ imports: [AdminQueuesModule], controllers: [AdminQueuesController] });
    admin = await t.seedUser("Alice Admin", { role: "admin" });
    athleteId = randomUUID();
    failEveryJob("segments");
    failEveryJob("activities");
  }, 30_000);

  afterAll(async () => {
    await Promise.all(workers.map((worker) => worker.close()));
    await Promise.all(connections.map((connection) => connection.quit()));
    await t?.sql("delete from audit.admin_audit_entry where actor_id = $1", [admin]);
    await t?.close();
  });

  it("lists every whitelisted queue with its counts, pause state and schedulers, unused ones empty", async () => {
    await queue("bucket-sweep").upsertJobScheduler(
      "bucket-sweep",
      { pattern: "0 3 * * *", tz: "UTC" },
      { name: "bucket-sweep" },
    );
    await queue("avatars").add("copy-google-avatar", {}, { delay: 3_600_000 });

    const response = await t.call("/admin/queues", admin);

    expect(response.status).toBe(200);
    const { items } = (await response.json()) as AdminQueueListResponse;
    expect(items.map((item) => item.name)).toEqual([
      "activities",
      "imports",
      "segments",
      "subscriptions",
      "avatars",
      "bucket-sweep",
      "accounts",
      "emails",
    ]);
    expect(items.map((item) => item.name)).toEqual([...ADMIN_QUEUE_NAMES]);
    expect(items.find((item) => item.name === "avatars")?.counts.delayed).toBe(1);
    expect(items.find((item) => item.name === "bucket-sweep")?.schedulers).toEqual([
      {
        id: "bucket-sweep",
        jobName: "bucket-sweep",
        everyMs: null,
        pattern: "0 3 * * *",
        timeZone: "UTC",
        nextRunAt: expect.any(String),
      },
    ]);
    expect(items.find((item) => item.name === "emails")).toEqual({
      name: "emails",
      isPaused: false,
      counts: { waiting: 0, active: 0, delayed: 0, prioritized: 0, waitingChildren: 0, completed: 0, failed: 0 },
      schedulers: [],
    });
  });

  it("pages the failed jobs of a queue, newest first, and opens one read-only with its links", async () => {
    const activityId = randomUUID();
    const older = await failedJob("segments", "match-segments", { activityId, userId: athleteId });
    const newer = await failedJob("segments", "match-segments", { activityId: randomUUID(), userId: athleteId });

    const list = (await (
      await t.call("/admin/queues/segments/jobs?state=failed&pageSize=25", admin)
    ).json()) as AdminQueueJobListResponse;

    expect(list.total).toBeGreaterThanOrEqual(2);
    expect(list.items.map((item) => item.id).slice(0, 2)).toEqual([newer.id, older.id]);
    expect(list.items[1]).toMatchObject({
      id: older.id,
      name: "match-segments",
      queue: "segments",
      failedReason: "boom match-segments",
      attemptsMade: 1,
      maxAttempts: 1,
      retryRefused: false,
    });

    const detail = (await (await t.call(`/admin/queues/segments/jobs/${older.id}`, admin)).json()) as AdminQueueJobDetail;
    expect(detail).toMatchObject({
      id: older.id,
      state: "failed",
      data: { activityId, userId: athleteId },
      activityId,
      userId: athleteId,
    });
    expect(detail.stacktrace[0]).toContain("boom match-segments");
  });

  it("retries one failed job with its attempts reset, and records it", async () => {
    const job = await failedJob("segments", "match-segments", { activityId: randomUUID() });
    await queue("segments").pause();
    try {
      const response = await t.call(`/admin/queues/segments/jobs/${job.id}/retry`, admin, { method: "POST" });

      expect(response.status).toBe(204);
      const retried = await queue("segments").getJob(job.id!);
      expect(await retried!.getState()).toBe("waiting");
      expect(retried!.attemptsMade).toBe(0);
      expect(await journal("queue.job.retry")).toContainEqual(
        expect.objectContaining({ target_type: "job", target_id: `segments/${job.id}`, reason: null }),
      );
    } finally {
      await queue("segments").resume();
    }
  });

  it("refuses a raw retry of process-activity: « Retraiter » relaunches it", async () => {
    const job = await failedJob("activities", "process-activity", { activityId: randomUUID() });

    const response = await t.call(`/admin/queues/activities/jobs/${job.id}/retry`, admin, { method: "POST" });

    expect(response.status).toBe(409);
    expect(await errorCode(response)).toBe("retry_refused");
    expect(await job.getState()).toBe("failed");
    const detail = (await (await t.call(`/admin/queues/activities/jobs/${job.id}`, admin)).json()) as AdminQueueJobDetail;
    expect(detail.retryRefused).toBe(true);
  });

  it("answers 409 not_failed for a job that has not failed", async () => {
    const job = await queue("avatars").add("copy-google-avatar", {}, { delay: 3_600_000 });

    const response = await t.call(`/admin/queues/avatars/jobs/${job.id}/retry`, admin, { method: "POST" });

    expect(response.status).toBe(409);
    expect(await errorCode(response)).toBe("not_failed");
  });

  it("retries every failed job of a queue but the refused ones, with one Journal entry", async () => {
    const reprocess = await failedJob("activities", "reprocess-activity", { activityId: randomUUID() });
    const refused = await failedJob("activities", "process-activity", { activityId: randomUUID() });
    await queue("activities").pause();
    try {
      const response = await t.call("/admin/queues/activities/retry-failed", admin, { method: "POST" });

      expect(response.status).toBe(202);
      const body = (await response.json()) as AdminQueueRetryFailedResponse;
      expect(body.retried).toBeGreaterThanOrEqual(1);
      expect(body.refused).toBeGreaterThanOrEqual(1);
      expect(await reprocess.getState()).toBe("waiting");
      expect(await refused.getState()).toBe("failed");
      expect(await journal("queue.retry_failed")).toContainEqual(
        expect.objectContaining({ target_type: "queue", target_id: "activities", details: body }),
      );
    } finally {
      await queue("activities").resume();
    }
  });

  it("pauses and resumes a queue, each recorded", async () => {
    const pause = await t.call("/admin/queues/imports/pause", admin, { method: "POST" });
    expect(pause.status).toBe(204);
    expect(await queue("imports").isPaused()).toBe(true);
    const paused = (await (await t.call("/admin/queues", admin)).json()) as AdminQueueListResponse;
    expect(paused.items.find((item) => item.name === "imports")?.isPaused).toBe(true);

    const resume = await t.call("/admin/queues/imports/resume", admin, { method: "POST" });
    expect(resume.status).toBe(204);
    expect(await queue("imports").isPaused()).toBe(false);

    expect(await journal("queue.pause")).toContainEqual(expect.objectContaining({ target_type: "queue", target_id: "imports" }));
    expect(await journal("queue.resume")).toContainEqual(expect.objectContaining({ target_id: "imports" }));
  });

  it("answers 404 for a queue outside the whitelist and for an unknown job", async () => {
    const unknownQueue = await t.call("/admin/queues/media/jobs", admin);
    expect(unknownQueue.status).toBe(404);
    expect(await errorCode(unknownQueue)).toBe("queue_not_found");
    expect((await t.call("/admin/queues/media/pause", admin, { method: "POST" })).status).toBe(404);

    const unknownJob = await t.call("/admin/queues/segments/jobs/nope", admin);
    expect(unknownJob.status).toBe(404);
    expect(await errorCode(unknownJob)).toBe("job_not_found");
  });

  it("is refused to an athlete", async () => {
    expect((await t.call("/admin/queues", athleteId, { role: "user" })).status).toBe(403);
  });
});
