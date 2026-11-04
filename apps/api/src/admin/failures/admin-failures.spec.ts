import { randomUUID } from "node:crypto";
import { getQueueToken } from "@nestjs/bullmq";
import type { Queue } from "bullmq";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  ACTIVITIES_QUEUE_NAME,
  IMPORTS_QUEUE_NAME,
  importActivityJobId,
  processActivityJobId,
  type AdminBatchResponse,
  type AdminFailedActivityListResponse,
  type AdminFailedImportListResponse,
  type AdminStaleActivityListResponse,
} from "@repo/contracts";
import { ActivitiesModule } from "@repo/core/activities";
import { EngagementModule } from "@repo/core/engagement";
import { SegmentsModule } from "@repo/core/segments";
import { UsersModule } from "@repo/core/users";
import { AthleteIdentities } from "../../identities/athlete-identities.js";
import { MediaAssembler } from "../../media/media-assembler.js";
import type { AdminTestApp } from "../../testing/admin-test-app.js";
import { useExclusiveTestDatabase } from "../../testing/exclusive-test-database.js";
import { AdminActivitiesController } from "../activities/admin-activities.controller.js";
import { AdminActivityAssembler } from "../activities/admin-activity-assembler.js";
import { AdminActivityImportsController } from "../activity-imports/admin-activity-imports.controller.js";
import { SanctionNotices } from "../sanctions/sanction-notices.js";
import { AdminFailureAssembler } from "./admin-failure-assembler.js";
import { AdminFailuresController } from "./admin-failures.controller.js";

/**
 * The "Échecs" tab of the Jobs screen (ADR-038 §14): failed Activities, imports and
 * recomputations, their unit and batch relaunches, over real HTTP, Postgres and Redis.
 */
describe("/v1/admin failures (integration)", () => {
  let t: AdminTestApp;
  let admin: string;
  let emile: string;
  let zoe: string;

  const queue = (name: string) => t.app.get<Queue>(getQueueToken(name));

  async function seedActivity(values: {
    userId: string;
    status: "processing" | "processed" | "failed";
    title?: string;
    sport?: string;
    error?: string;
    createdAt?: string;
    computedFor?: string | null;
  }): Promise<string> {
    const id = randomUUID();
    const createdAt = values.createdAt ?? new Date().toISOString();
    await t.sql(
      `insert into activities.activity
         (id, user_id, sport_type_code, title, started_at, ended_at, visibility, processing_status,
          source, processing_error, processing_attempts, created_at, updated_at)
       values ($1, $2, $3, $4, '2026-11-02T08:00:00Z', '2026-11-02T09:00:00Z', 'public', $5, 'recorded',
               $6, 5, $7, $7)`,
      [id, values.userId, values.sport ?? "run", values.title ?? "Sortie", values.status, values.error ?? null, createdAt],
    );
    if (values.computedFor !== undefined) {
      await t.sql(
        `insert into activities.activity_stats (activity_id, distance_m, computed_for_sport_type_code)
         values ($1, 10000, $2)`,
        [id, values.computedFor],
      );
    }
    return id;
  }

  async function seedImport(values: { userId: string; status: "failed" | "imported"; createdAt?: string }) {
    const id = randomUUID();
    await t.sql(
      `insert into activities.activity_import
         (id, user_id, format, original_file_name, size_bytes, status, error, attempts, created_at, processed_at)
       values ($1, $2, 'gpx', 'sortie.gpx', 1000, $3, $4, 5, $5, $5)`,
      [
        id,
        values.userId,
        values.status,
        values.status === "failed" ? "processing_error" : null,
        values.createdAt ?? new Date().toISOString(),
      ],
    );
    return id;
  }

  async function journal(action: string) {
    return t.sql<{ target_type: string; target_id: string | null; subject_user_id: string | null; details: unknown }>(
      "select * from audit.admin_audit_entry where action = $1",
      [action],
    );
  }

  const errorCode = async (response: Response) =>
    ((await response.json()) as { error: { code: string } }).error.code;

  beforeAll(async () => {
    // Global lists and batches over every failure: this file runs on a database of its own. The
    // test apps read `TEST_DATABASE_URL` once, when imported: point it there first, then import.
    await useExclusiveTestDatabase("admin_failures");
    const { bootstrapAdminTestApp } = await import("../../testing/admin-test-app.js");
    t = await bootstrapAdminTestApp({
      imports: [ActivitiesModule, EngagementModule, SegmentsModule, UsersModule],
      controllers: [AdminFailuresController, AdminActivitiesController, AdminActivityImportsController],
      providers: [
        AdminFailureAssembler, AdminActivityAssembler, AthleteIdentities, MediaAssembler,
        // The e-mail hook is covered by `sanction-notices.spec.ts`: here only the notice handed over.
        { provide: SanctionNotices, useValue: { send: async () => undefined } },
      ],
    });
    admin = await t.seedUser("Alice Admin", { role: "admin" });
    emile = await t.seedUser("Émile Durand");
    zoe = await t.seedUser("Zoé Martin");
  }, 60_000);

  beforeEach(async () => {
    await t.sql("delete from activities.activity_import");
    await t.sql("delete from activities.activity");
    await t.sql("delete from audit.admin_audit_entry");
  });

  afterAll(async () => {
    await t?.close();
  });

  describe("lists", () => {
    it("lists failed Activities, newest first, with the worker's error, attempts and athlete", async () => {
      const older = await seedActivity({
        userId: emile,
        status: "failed",
        title: "Footing",
        error: "invalid_trace",
        createdAt: "2026-11-01T08:00:00Z",
      });
      const newer = await seedActivity({ userId: zoe, status: "failed", error: "timeout", createdAt: "2026-11-02T08:00:00Z" });
      await seedActivity({ userId: zoe, status: "processed" });

      const response = await t.call("/admin/failures/activities?pageSize=25", admin);

      expect(response.status).toBe(200);
      const page = (await response.json()) as AdminFailedActivityListResponse;
      expect(page).toMatchObject({ total: 2, page: 1, pageSize: 25 });
      expect(page.items.map((item) => item.id)).toEqual([newer, older]);
      expect(page.items[1]).toMatchObject({
        id: older,
        title: "Footing",
        athlete: { id: emile, displayName: "Émile Durand" },
        sportTypeCode: "run",
        processingError: "invalid_trace",
        processingAttempts: 5,
        createdAt: "2026-11-01T08:00:00.000Z",
      });
    });

    it("lists failed imports, newest first, with their error, attempts and athlete", async () => {
      const failed = await seedImport({ userId: emile, status: "failed" });
      await seedImport({ userId: emile, status: "imported" });

      const page = (await (await t.call("/admin/failures/imports", admin)).json()) as AdminFailedImportListResponse;

      expect(page.total).toBe(1);
      expect(page.items[0]).toMatchObject({
        id: failed,
        athlete: { id: emile, displayName: "Émile Durand" },
        format: "gpx",
        fileName: "sortie.gpx",
        error: "processing_error",
        attempts: 5,
      });
    });

    it("lists processed Activities whose values were computed for another sport", async () => {
      const stale = await seedActivity({ userId: zoe, status: "processed", sport: "ride", computedFor: "run" });
      await seedActivity({ userId: zoe, status: "processed", sport: "run", computedFor: "run" });

      const page = (await (await t.call("/admin/failures/recomputes", admin)).json()) as AdminStaleActivityListResponse;

      expect(page.total).toBe(1);
      expect(page.items[0]).toMatchObject({
        id: stale,
        athlete: { id: zoe, displayName: "Zoé Martin" },
        sportTypeCode: "ride",
        computedForSportTypeCode: "run",
      });
    });

    it("is refused to an athlete", async () => {
      expect((await t.call("/admin/failures/activities", emile, { role: "user" })).status).toBe(403);
    });
  });

  describe("« Recalculer »", () => {
    it("enqueues reprocess-activity under a new job id at each click and records it", async () => {
      const stale = await seedActivity({ userId: zoe, status: "processed", sport: "ride", computedFor: "run" });

      const first = await t.call(`/admin/activities/${stale}/recompute`, admin, { method: "POST" });
      const second = await t.call(`/admin/activities/${stale}/recompute`, admin, { method: "POST" });

      expect(first.status).toBe(202);
      const { jobId: firstJobId } = (await first.json()) as { jobId: string };
      const { jobId: secondJobId } = (await second.json()) as { jobId: string };
      expect(firstJobId).toMatch(new RegExp(`^reprocess-activity-${stale}-\\d+$`));
      expect(secondJobId).not.toBe(firstJobId);
      const job = await queue(ACTIVITIES_QUEUE_NAME).getJob(firstJobId);
      expect(job).toMatchObject({ name: "reprocess-activity", data: { activityId: stale, userId: zoe } });
      expect(await journal("activity.recompute")).toEqual([
        expect.objectContaining({ target_type: "activity", target_id: stale, subject_user_id: zoe }),
        expect.objectContaining({ target_id: stale }),
      ]);
    });

    it("answers 409 not_stale for an Activity whose values are up to date, 404 for an unknown one", async () => {
      const fresh = await seedActivity({ userId: zoe, status: "processed", computedFor: "run" });

      const response = await t.call(`/admin/activities/${fresh}/recompute`, admin, { method: "POST" });
      expect(response.status).toBe(409);
      expect(await errorCode(response)).toBe("not_stale");
      expect((await t.call(`/admin/activities/${randomUUID()}/recompute`, admin, { method: "POST" })).status).toBe(404);
      expect(await journal("activity.recompute")).toEqual([]);
    });
  });

  describe("batches", () => {
    it("« Retraiter les N en échec » relaunches every failed Activity, with one Journal entry", async () => {
      const failed = [
        await seedActivity({ userId: emile, status: "failed" }),
        await seedActivity({ userId: zoe, status: "failed" }),
      ];
      const processed = await seedActivity({ userId: zoe, status: "processed" });

      const response = await t.call("/admin/activities/reprocess-failed", admin, { method: "POST" });

      expect(response.status).toBe(202);
      expect((await response.json()) as AdminBatchResponse).toEqual({ relaunched: 2 });
      const statuses = await t.sql<{ id: string; processing_status: string }>(
        "select id, processing_status from activities.activity",
      );
      expect(Object.fromEntries(statuses.map((row) => [row.id, row.processing_status]))).toEqual({
        [failed[0]!]: "processing",
        [failed[1]!]: "processing",
        [processed]: "processed",
      });
      for (const id of failed) {
        expect(await queue(ACTIVITIES_QUEUE_NAME).getJob(processActivityJobId(id))).toBeDefined();
      }
      const [entry, ...others] = await journal("activity.reprocess.batch");
      expect(others).toEqual([]);
      expect(entry).toMatchObject({ target_type: "activity", target_id: null, subject_user_id: null });
      expect(entry!.details).toEqual({ count: 2, ids: expect.arrayContaining(failed) });
    });

    it("relaunches 500 failed Activities at most per click", async () => {
      await t.sql(
        `insert into activities.activity
           (id, user_id, sport_type_code, title, started_at, ended_at, visibility, processing_status, source)
         select gen_random_uuid(), $1, 'run', 'Sortie', now(), now(), 'public', 'failed', 'recorded'
         from generate_series(1, 501)`,
        [emile],
      );

      const response = await t.call("/admin/activities/reprocess-failed", admin, { method: "POST" });

      expect((await response.json()) as AdminBatchResponse).toEqual({ relaunched: 500 });
      const [left] = await t.sql<{ count: string }>(
        "select count(*) from activities.activity where processing_status = 'failed'",
      );
      expect(left!.count).toBe("1");
    }, 60_000);

    it("« Recalculer les N en échec » relaunches every stale Activity under new job ids", async () => {
      const stale = await seedActivity({ userId: zoe, status: "processed", sport: "ride", computedFor: "run" });
      await seedActivity({ userId: zoe, status: "processed", computedFor: "run" });

      const response = await t.call("/admin/activities/recompute-stale", admin, { method: "POST" });

      expect((await response.json()) as AdminBatchResponse).toEqual({ relaunched: 1 });
      const jobs = await queue(ACTIVITIES_QUEUE_NAME).getJobs(["waiting"]);
      expect(jobs.filter((job) => job.data.activityId === stale).map((job) => job.name)).toEqual(["reprocess-activity"]);
      const [entry] = await journal("activity.recompute.batch");
      expect(entry!.details).toEqual({ count: 1, ids: [stale] });
    });

    it("« Retraiter les N en échec » relaunches every failed import", async () => {
      const failed = await seedImport({ userId: emile, status: "failed" });
      await seedImport({ userId: emile, status: "imported" });

      const response = await t.call("/admin/activity-imports/reprocess-failed", admin, { method: "POST" });

      expect(response.status).toBe(202);
      expect((await response.json()) as AdminBatchResponse).toEqual({ relaunched: 1 });
      expect(await queue(IMPORTS_QUEUE_NAME).getJob(importActivityJobId(failed))).toBeDefined();
      const [entry] = await journal("import.reprocess.batch");
      expect(entry).toMatchObject({ target_type: "activity_import", target_id: null });
      expect(entry!.details).toEqual({ count: 1, ids: [failed] });
    });

    it("relaunches nothing and still records the click when nothing failed", async () => {
      const response = await t.call("/admin/activities/reprocess-failed", admin, { method: "POST" });

      expect((await response.json()) as AdminBatchResponse).toEqual({ relaunched: 0 });
      expect((await journal("activity.reprocess.batch"))[0]!.details).toEqual({ count: 0, ids: [] });
    });
  });
});
