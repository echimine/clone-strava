import { randomUUID } from "node:crypto";
import { getQueueToken } from "@nestjs/bullmq";
import { Worker, type Queue } from "bullmq";
import { Redis } from "ioredis";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import type { AdminGrowthStats, AdminTodoStats } from "@repo/contracts";
import { AuthService } from "@repo/core/auth";
import { bootstrapTestAuthApp, TEST_REDIS_URL, type TestAuthApp } from "../../auth/test-auth-app.js";
import { bootstrapAdminTestApp, type AdminTestApp } from "../../testing/admin-test-app.js";
import { AdminStatsController } from "./admin-stats.controller.js";
import { ADMIN_STATS_IMPORTS, ADMIN_STATS_PROVIDERS, StatsClock } from "./admin-stats.providers.js";

/**
 * The stats are global counts: this file runs on a database of its own, so the spec files running
 * in parallel cannot move them. Each assertion is still a difference between two reads around the
 * test's own seeds (the tests share the file's data), and the clock is set in 2030.
 */
await vi.hoisted(async () => {
  const { useExclusiveTestDatabase } = await import("../../testing/exclusive-test-database.js");
  await useExclusiveTestDatabase("admin_stats");
});

const NOW = new Date("2030-01-15T12:00:00Z");

/** `after - before` on every number of a stats response (strings and arrays of days untouched). */
function difference<T>(after: T, before: T): T {
  if (typeof after === "number" && typeof before === "number") {
    return (after - before) as T;
  }
  if (Array.isArray(after) && Array.isArray(before)) {
    return after.map((item, index) => difference(item, before[index])) as T;
  }
  if (after && typeof after === "object" && before && typeof before === "object") {
    return Object.fromEntries(
      Object.entries(after).map(([key, value]) => [key, difference(value, (before as Record<string, unknown>)[key])]),
    ) as T;
  }
  return after;
}

describe("Backoffice dashboard stats (ADR-038 §15, integration)", () => {
  let t: AdminTestApp;
  let authApp: TestAuthApp;
  let admin: string;

  beforeAll(async () => {
    // Sign-ups and the Administrators left out come from the real `auth` module.
    authApp = await bootstrapTestAuthApp();
    const auth = authApp.app.get(AuthService);
    t = await bootstrapAdminTestApp({
      imports: ADMIN_STATS_IMPORTS,
      controllers: [AdminStatsController],
      providers: [
        ...ADMIN_STATS_PROVIDERS.filter((provider) => provider !== StatsClock),
        { provide: StatsClock, useValue: { now: () => NOW } },
      ],
      authService: {
        listAdminIds: () => auth.listAdminIds(),
        countSignUpsPerParisDay: (range: { start: Date; end: Date }) => auth.countSignUpsPerParisDay(range),
      },
    });
    admin = await t.seedUser("Alice Admin", { role: "admin" });
  });

  afterAll(async () => {
    await t?.close();
    await authApp?.app.close();
  });

  async function get<T>(path: string): Promise<T> {
    const response = await t.call(path, admin);
    expect(response.status).toBe(200);
    return (await response.json()) as T;
  }

  async function seedActivity(
    userId: string,
    startedAt: string,
    options: { source?: string; status?: string } = {},
  ): Promise<string> {
    const id = randomUUID();
    const start = new Date(startedAt);
    await t.sql(
      `insert into activities.activity (id, user_id, sport_type_code, title, started_at, ended_at, source, processing_status)
       values ($1, $2, 'run', 'Sortie', $3, $4, $5, $6)`,
      [id, userId, start, new Date(start.getTime() + 3_600_000), options.source ?? "recorded", options.status ?? "processed"],
    );
    return id;
  }

  async function signedUpAt(userId: string, createdAt: string): Promise<void> {
    await t.sql('update "user" set created_at = $2 where id = $1', [userId, createdAt]);
  }

  it("is for Administrators only", async () => {
    const response = await t.call("/admin/stats/todo", admin, { role: "user" });
    expect(response.status).toBe(403);
  });

  describe("GET /v1/admin/stats/todo", () => {
    it("counts failed Activities, imports failed in the last 7 days and failed jobs of every queue", async () => {
      const before = await get<AdminTodoStats>("/admin/stats/todo");

      const athlete = await t.seedUser("Athlète Échecs");
      await seedActivity(athlete, "2030-01-10T08:00:00Z", { status: "failed" });
      await seedActivity(athlete, "2030-01-11T08:00:00Z", { status: "failed" });
      await seedActivity(athlete, "2030-01-12T08:00:00Z", { status: "processed" });
      const seedImport = (status: string, processedAt: string | null) =>
        t.sql(
          `insert into activities.activity_import (id, user_id, format, original_file_name, size_bytes, status, error, processed_at)
           values ($1, $2, 'gpx', 'run.gpx', 1000, $3, 'unreadable_file', $4)`,
          [randomUUID(), athlete, status, processedAt],
        );
      await seedImport("failed", "2030-01-14T09:00:00Z");
      await seedImport("failed", "2030-01-08T13:00:00Z");
      await seedImport("failed", "2030-01-08T11:00:00Z"); // more than 7 days before NOW
      await seedImport("imported", "2030-01-14T09:00:00Z");
      await failJob("avatars");
      await failJob("segments");

      const after = await get<AdminTodoStats>("/admin/stats/todo");

      expect(difference(after, before)).toMatchObject({
        failedActivities: 2,
        failedImports: 2,
        failedJobs: 2,
      });
    });

    it("shows 0 for the tiles whose data does not exist yet", async () => {
      const todo = await get<AdminTodoStats>("/admin/stats/todo");

      expect(todo.openReports).toEqual({ count: 0, oldestOpenedAt: null });
      expect(todo.suspiciousEfforts).toBe(0);
    });
  });

  describe("GET /v1/admin/stats/growth", () => {
    it("defaults to the last 30 Paris days, one chart point per day", async () => {
      const growth = await get<AdminGrowthStats>("/admin/stats/growth");

      expect(growth).toMatchObject({ period: "30d", from: "2029-12-17", to: "2030-01-15" });
      expect(growth.daily).toHaveLength(30);
      expect(growth.daily[0]?.day).toBe("2029-12-17");
    });

    it("refuses another period", async () => {
      const response = await t.call("/admin/stats/growth?period=12d", admin);
      expect(response.status).toBe(422);
    });

    it("counts the period against the previous one, by Paris day, without Administrators nor Sandbox", async () => {
      const before = await get<AdminGrowthStats>("/admin/stats/growth?period=7d");

      // Period: 9–15 January 2030 (Paris); previous period: 2–8 January.
      const anna = await t.seedUser("Anna");
      const bruno = await t.seedUser("Bruno");
      const chloe = await t.seedUser("Chloé");
      const otherAdmin = await t.seedUser("Admin Bis", { role: "admin" });
      await signedUpAt(anna, "2030-01-10T10:00:00Z");
      await signedUpAt(bruno, "2030-01-05T10:00:00Z");
      await signedUpAt(chloe, "2029-11-01T10:00:00Z");
      await signedUpAt(otherAdmin, "2030-01-12T10:00:00Z");

      const annaRun = await seedActivity(anna, "2030-01-10T10:00:00Z");
      // 23:30 in Paris on 14 January.
      await seedActivity(anna, "2030-01-14T22:30:00Z", { source: "imported" });
      await seedActivity(bruno, "2030-01-11T07:00:00Z", { source: "manual", status: "failed" });
      await seedActivity(bruno, "2030-01-03T07:00:00Z");
      // 00:30 in Paris on 16 January: after the period.
      await seedActivity(bruno, "2030-01-15T23:30:00Z");
      await seedActivity(chloe, "2029-12-01T07:00:00Z");
      const adminRun = await seedActivity(otherAdmin, "2030-01-12T07:00:00Z");

      await t.sql(
        `insert into engagement.kudos (user_id, activity_id, created_at)
         values ($1, $3, '2030-01-12T09:00:00Z'), ($2, $3, '2030-01-12T09:00:00Z'), ($1, $4, '2030-01-04T09:00:00Z')`,
        [bruno, otherAdmin, annaRun, adminRun],
      );
      await t.sql(
        `insert into engagement.comment (activity_id, user_id, body, created_at, deleted_at)
         values ($1, $2, 'Bravo', '2030-01-13T09:00:00Z', null),
                ($1, $2, 'Oups', '2030-01-13T09:05:00Z', '2030-01-13T09:06:00Z'),
                ($1, $3, 'Salut', '2030-01-13T09:00:00Z', null)`,
        [annaRun, bruno, otherAdmin],
      );
      await t.sql(
        `insert into social.follow (follower_id, followee_id, status, created_at)
         values ($1, $2, 'accepted', '2030-01-12T09:00:00Z'),
                ($2, $1, 'pending', '2030-01-12T09:00:00Z'),
                ($3, $1, 'accepted', '2030-01-12T09:00:00Z'),
                ($4, $1, 'accepted', '2030-01-06T09:00:00Z')`,
        [anna, bruno, otherAdmin, chloe],
      );
      await t.sql(
        `insert into activities.activity_media (activity_id, s3_key, kind, width, height, created_at)
         values ($1, 'k1', 'photo', 10, 10, '2030-01-13T09:00:00Z'), ($2, 'k2', 'photo', 10, 10, '2030-01-13T09:00:00Z')`,
        [annaRun, adminRun],
      );

      const dave = await t.seedUser("Dave");
      const emma = await t.seedUser("Emma");
      await t.sql(
        `insert into subscriptions.user_subscription (user_id, is_active, period_type, environment, expires_at)
         values ($1, true, 'normal', 'production', '2030-02-01T00:00:00Z'),
                ($2, true, 'trial', 'production', '2030-01-20T00:00:00Z'),
                ($3, true, 'normal', 'sandbox', '2030-02-01T00:00:00Z'),
                ($4, true, 'normal', 'production', '2030-01-01T00:00:00Z'),
                ($5, true, 'normal', 'production', '2030-02-01T00:00:00Z')`,
        [anna, bruno, chloe, dave, otherAdmin],
      );
      const event = (
        userId: string,
        type: string,
        receivedAt: string,
        details: { period_type: string; environment?: string; is_trial_conversion?: boolean },
      ) =>
        t.sql(
          "insert into subscriptions.revenuecat_event (id, user_id, type, payload, received_at) values ($1, $2, $3, $4, $5)",
          [
            randomUUID(),
            userId,
            type,
            { api_version: "1.0", event: { type, environment: "PRODUCTION", ...details } },
            receivedAt,
          ],
        );
      await event(bruno, "INITIAL_PURCHASE", "2030-01-11T09:00:00Z", { period_type: "TRIAL" });
      await event(anna, "INITIAL_PURCHASE", "2030-01-12T09:00:00Z", { period_type: "NORMAL" });
      await event(emma, "RENEWAL", "2030-01-04T09:00:00Z", { period_type: "NORMAL", is_trial_conversion: true });
      await event(anna, "RENEWAL", "2030-01-13T09:00:00Z", { period_type: "NORMAL", is_trial_conversion: false });
      await event(chloe, "INITIAL_PURCHASE", "2030-01-12T09:00:00Z", { period_type: "TRIAL", environment: "SANDBOX" });
      await event(otherAdmin, "INITIAL_PURCHASE", "2030-01-12T09:00:00Z", { period_type: "TRIAL" });

      const after = await get<AdminGrowthStats>("/admin/stats/growth?period=7d");

      expect(after).toMatchObject({ period: "7d", from: "2030-01-09", to: "2030-01-15" });
      const trend = (value: number, previous: number) => ({ value, previous });
      const { daily, ...counts } = difference(after, before);
      expect(counts).toEqual({
        period: "7d",
        from: "2030-01-09",
        to: "2030-01-15",
        signUps: trend(1, 1),
        activeAthletes: trend(2, 1),
        activities: {
          total: trend(3, 1),
          recorded: trend(1, 1),
          imported: trend(1, 0),
          manual: trend(1, 0),
        },
        premium: {
          payingActive: 1,
          trialsActive: 1,
          promotionalActive: 0,
          trialsStarted: trend(1, 0),
          newPaying: trend(1, 1),
        },
        engagement: {
          kudos: trend(1, 1),
          comments: trend(1, 0),
          follows: trend(1, 1),
          media: trend(1, 0),
        },
      });
      expect(daily.filter((point) => point.signUps !== 0 || point.activities !== 0)).toEqual([
        { day: "2030-01-10", signUps: 1, activities: 1 },
        { day: "2030-01-11", signUps: 0, activities: 1 },
        { day: "2030-01-14", signUps: 0, activities: 1 },
      ]);
    });
  });

  /** Adds a job to `queueName` and lets a stand-in worker fail it once and for all. */
  async function failJob(queueName: string): Promise<void> {
    const queue = t.app.get<Queue>(getQueueToken(queueName), { strict: false });
    const connection = new Redis(TEST_REDIS_URL, { maxRetriesPerRequest: null });
    const worker = new Worker(
      queueName,
      async () => {
        throw new Error("probe failure");
      },
      { connection, prefix: queue.opts.prefix },
    );
    try {
      const job = await queue.add("probe", {}, { attempts: 1 });
      const deadline = Date.now() + 5_000;
      while ((await job.getState()) !== "failed") {
        if (Date.now() > deadline) {
          throw new Error(`job ${job.id} of ${queueName} never failed`);
        }
        await new Promise((resolve) => setTimeout(resolve, 20));
      }
    } finally {
      await worker.close();
      await connection.quit().catch(() => undefined);
    }
  }
});
