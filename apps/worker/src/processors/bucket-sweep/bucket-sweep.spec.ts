import { randomUUID } from "node:crypto";
import { getQueueToken } from "@nestjs/bullmq";
import type { Queue } from "bullmq";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import {
  activityImportSourceKey,
  activityMediaKey,
  activityMediaPrefix,
  activityTraceKey,
  avatarKey,
} from "@repo/contracts";
import { ActivitiesService } from "@repo/core/activities";
import { bootstrapTestWorkerApp, waitFor, type TestWorkerApp } from "../../testing/test-worker-app.js";
import { BUCKET_SWEEP_JOB_NAME, BUCKET_SWEEP_QUEUE_NAME } from "./bucket-sweep.processor.js";
import { BucketSweepScheduler } from "./bucket-sweep.scheduler.js";

const DAY_MS = 24 * 3_600_000;
const eightDaysAgo = () => new Date(Date.now() - 8 * DAY_MS);
const sixDaysAgo = () => new Date(Date.now() - 6 * DAY_MS);

/**
 * The daily `bucket-sweep` (ADR-037 §11) on real Postgres and Redis, the bucket in memory: it
 * deletes the folders nothing references once their newest object is more than 7 days old.
 */
describe("bucket-sweep (integration)", () => {
  let ctx: TestWorkerApp;
  let userId: string;

  async function sql(text: string, params: unknown[]) {
    return (await ctx.db.$client.query(text, params)).rows;
  }

  /** Puts an object in the bucket, last modified at `at`. */
  function put(key: string, at: Date): string {
    ctx.storage.objects.set(key, new Uint8Array([1]));
    ctx.storage.lastModified.set(key, at);
    return key;
  }

  const has = (key: string) => ctx.storage.objects.has(key);

  function queue(): Queue {
    return ctx.app.get<Queue>(getQueueToken(BUCKET_SWEEP_QUEUE_NAME));
  }

  /** Runs one sweep through the queue, as the daily schedule does. */
  async function sweep(): Promise<void> {
    const job = await queue().add(BUCKET_SWEEP_JOB_NAME, {});
    await waitFor(async () => {
      const state = await job.getState();
      if (state === "failed") throw new Error("bucket-sweep failed");
      return state === "completed" ? true : undefined;
    });
  }

  /** A pending Activity of `userId`: its row exists. */
  async function activity(): Promise<string> {
    const id = randomUUID();
    await ctx.app.get(ActivitiesService).create(userId, {
      id,
      sportTypeCode: "run",
      title: "Sortie",
      startedAt: new Date(Date.now() - 3_600_000).toISOString(),
      endedAt: new Date(Date.now() - 1_800_000).toISOString(),
      visibility: "public",
      isManual: false,
    });
    return id;
  }

  /** A confirmed Media of `activityId`: its `activity_media` row exists. */
  async function confirmedMedia(activityId: string): Promise<string> {
    const id = randomUUID();
    await sql(
      `insert into activities.activity_media (id, activity_id, s3_key, kind, width, height, position)
       values ($1, $2, $3, 'photo', 2048, 1536, 0)`,
      [id, activityId, activityMediaPrefix(userId, activityId, id)],
    );
    return id;
  }

  beforeAll(async () => {
    ctx = await bootstrapTestWorkerApp();
    userId = randomUUID();
    await sql('insert into "user" (id, name, email) values ($1, $2, $3)', [
      userId,
      "Sweep test",
      `${userId}@test.local`,
    ]);
  }, 30_000);

  afterAll(async () => {
    if (userId) {
      // Cascades to the user's profile, activities and imports.
      await sql('delete from "user" where id = $1', [userId]);
    }
    await ctx?.close();
  });

  it("deletes an old Activity folder without its activity row, and keeps a recent one", async () => {
    const gone = randomUUID();
    const oldTrace = put(activityTraceKey(userId, gone), eightDaysAgo());
    const oldMedia = put(activityMediaKey(userId, gone, randomUUID(), "thumb.jpg"), eightDaysAgo());
    // Judged by its newest object: a late `PUT` keeps the whole folder.
    const lately = randomUUID();
    const lateTrace = put(activityTraceKey(userId, lately), eightDaysAgo());
    const lateMedia = put(activityMediaKey(userId, lately, randomUUID(), "original.jpg"), sixDaysAgo());

    await sweep();

    expect(has(oldTrace)).toBe(false);
    expect(has(oldMedia)).toBe(false);
    expect(has(lateTrace)).toBe(true);
    expect(has(lateMedia)).toBe(true);
  });

  it("keeps an old Activity folder whose activity exists", async () => {
    const id = await activity();
    const trace = put(activityTraceKey(userId, id), eightDaysAgo());

    await sweep();

    expect(has(trace)).toBe(true);
  });

  it("deletes an old Media folder without its activity_media row, keeps confirmed and recent ones", async () => {
    const id = await activity();
    const confirmed = await confirmedMedia(id);
    const confirmedFiles = [
      put(activityMediaKey(userId, id, confirmed, "original.jpg"), eightDaysAgo()),
      put(activityMediaKey(userId, id, confirmed, "thumb.jpg"), eightDaysAgo()),
    ];
    const abandoned = randomUUID();
    const abandonedFiles = [
      put(activityMediaKey(userId, id, abandoned, "original.mp4"), eightDaysAgo()),
      put(activityMediaKey(userId, id, abandoned, "poster.jpg"), eightDaysAgo()),
    ];
    const sending = put(activityMediaKey(userId, id, randomUUID(), "original.jpg"), sixDaysAgo());
    const trace = put(activityTraceKey(userId, id), eightDaysAgo());

    await sweep();

    expect(abandonedFiles.map(has)).toEqual([false, false]);
    expect(confirmedFiles.map(has)).toEqual([true, true]);
    expect(has(sending)).toBe(true);
    expect(has(trace)).toBe(true);
  });

  it("deletes an old import folder with neither import nor Activity, keeps the referenced and recent ones", async () => {
    const orphan = put(activityImportSourceKey(userId, randomUUID(), "gpx"), eightDaysAgo());
    const recent = put(activityImportSourceKey(userId, randomUUID(), "gpx"), sixDaysAgo());
    const importId = randomUUID();
    await sql(
      `insert into activities.activity_import (id, user_id, format, original_file_name, size_bytes)
       values ($1, $2, 'gpx', 'sortie.gpx', 1024)`,
      [importId, userId],
    );
    const ofImport = put(activityImportSourceKey(userId, importId, "gpx"), eightDaysAgo());
    // The import id is the Activity id (ADR-028 §1).
    const ofActivity = put(activityImportSourceKey(userId, await activity(), "fit"), eightDaysAgo());

    await sweep();

    expect(has(orphan)).toBe(false);
    expect(has(recent)).toBe(true);
    expect(has(ofImport)).toBe(true);
    expect(has(ofActivity)).toBe(true);
  });

  it("deletes old Avatars that are not the athlete's avatar_key, keeps the current and recent ones", async () => {
    const current = put(avatarKey(userId, randomUUID()), eightDaysAgo());
    await sql(
      `insert into users.user_profile (user_id, avatar_key) values ($1, $2)
       on conflict (user_id) do update set avatar_key = excluded.avatar_key`,
      [userId, current],
    );
    const replaced = put(avatarKey(userId, randomUUID()), eightDaysAgo());
    const recent = put(avatarKey(userId, randomUUID()), sixDaysAgo());
    // An athlete without a profile row has no current Avatar.
    const ofNoProfile = put(avatarKey(randomUUID(), randomUUID()), eightDaysAgo());

    await sweep();

    expect(has(current)).toBe(true);
    expect(has(replaced)).toBe(false);
    expect(has(recent)).toBe(true);
    expect(has(ofNoProfile)).toBe(false);
  });

  it("is scheduled once a day, and registering again on a restart keeps a single schedule", async () => {
    const [scheduler] = await queue().getJobSchedulers();
    expect(scheduler).toMatchObject({ name: BUCKET_SWEEP_JOB_NAME, pattern: "0 3 * * *" });
    expect(scheduler!.next! - Date.now()).toBeLessThanOrEqual(DAY_MS);

    await ctx.app.get(BucketSweepScheduler).onModuleInit();

    const schedulers = await queue().getJobSchedulers();
    expect(schedulers).toHaveLength(1);
    expect(schedulers[0]!.next).toBe(scheduler!.next);
  });
});
