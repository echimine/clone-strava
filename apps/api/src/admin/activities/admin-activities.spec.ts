import { randomUUID } from "node:crypto";
import { getQueueToken } from "@nestjs/bullmq";
import type { Queue } from "bullmq";
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi, type MockInstance } from "vitest";
import {
  ACTIVITIES_QUEUE_NAME,
  activityMediaPrefix,
  processActivityJobId,
  type AdminActivityDetail,
  type AdminActivityListResponse,
} from "@repo/contracts";
import type { AdminTestApp } from "../../testing/admin-test-app.js";
import { SanctionNotices } from "../sanctions/sanction-notices.js";
import { bootstrapAdminActivities, errorCode, type AdminActivitiesFixture } from "./admin-activities.fixture.js";

/**
 * The backoffice Activities screen (ADR-038 §11): list, detail and « Retraiter », over real HTTP,
 * Postgres and Redis (ADR-024 §2). Its Sanctions are in `admin-activity-sanctions.spec.ts`.
 */
describe("/v1/admin/activities (integration)", () => {
  let t: AdminTestApp;
  let admin: string;
  let emile: string;
  let zoe: string;
  let tag: string;
  let seedActivity: AdminActivitiesFixture["seedActivity"];
  let journal: AdminActivitiesFixture["journal"];
  let notices: MockInstance<SanctionNotices["send"]>;

  async function list(query: string): Promise<AdminActivityListResponse> {
    const response = await t.call(`/admin/activities?q=${tag}&${query}`, admin);
    expect(response.status).toBe(200);
    return (await response.json()) as AdminActivityListResponse;
  }

  beforeAll(async () => {
    ({ t, admin, emile, zoe, tag, seedActivity, journal } = await bootstrapAdminActivities());
  }, 30_000);

  beforeEach(() => {
    notices = vi.spyOn(t.app.get(SanctionNotices), "send");
  });

  afterAll(async () => {
    vi.restoreAllMocks();
    await t?.sql("delete from audit.admin_audit_entry where actor_id = $1", [admin]);
    await t?.close();
  });

  describe("list", () => {
    let emilePrivate: string;
    let zoeFailed: string;
    let emileImported: string;

    beforeAll(async () => {
      emilePrivate = await seedActivity({
        userId: emile,
        title: `Footing privé ${tag}`,
        visibility: "private",
        createdAt: "2026-11-03T10:00:00Z",
        startedAt: "2026-11-01T23:30:00Z", // 00:30 on 2 November in Paris
      });
      zoeFailed = await seedActivity({
        userId: zoe,
        title: `Vélo ${tag}`,
        sport: "ride",
        status: "failed",
        error: "invalid_trace",
        createdAt: "2026-11-03T11:00:00Z",
        startedAt: "2026-10-20T08:00:00Z",
      });
      emileImported = await seedActivity({
        userId: emile,
        title: `Import ${tag}`,
        source: "imported",
        createdAt: "2026-11-03T09:00:00Z",
        startedAt: "2026-11-01T22:30:00Z", // 23:30 on 1 November in Paris
      });
    });

    it("lists every Activity, private ones included, newest created first, with its athlete", async () => {
      const page = await list("");

      expect(page.total).toBe(3);
      expect(page.items.map((item) => item.id)).toEqual([zoeFailed, emilePrivate, emileImported]);
      expect(page.items[1]).toMatchObject({
        id: emilePrivate,
        title: `Footing privé ${tag}`,
        athlete: { id: emile, displayName: "Émile Durand" },
        visibility: "private",
        processingStatus: "processed",
        source: "recorded",
        sportTypeCode: "run",
        startedAt: "2026-11-01T23:30:00.000Z",
      });
    });

    it("filters by status, source, sport, visibility, athlete and Paris days of the start", async () => {
      expect((await list("status=failed")).items.map((item) => item.id)).toEqual([zoeFailed]);
      expect((await list("source=imported")).items.map((item) => item.id)).toEqual([emileImported]);
      expect((await list("sportTypeCode=ride")).items.map((item) => item.id)).toEqual([zoeFailed]);
      expect((await list("visibility=private")).items.map((item) => item.id)).toEqual([emilePrivate]);
      expect((await list(`userId=${emile}`)).items.map((item) => item.id)).toEqual([emilePrivate, emileImported]);
      expect((await list("from=2026-11-02&to=2026-11-02")).items.map((item) => item.id)).toEqual([emilePrivate]);
    });

    it("searches the title and the athlete's name or e-mail, ignoring case and accents", async () => {
      const byName = await t.call(`/admin/activities?q=emile%20durand`, admin);
      const names = (await byName.json()) as AdminActivityListResponse;
      expect(names.items.map((item) => item.id)).toEqual(expect.arrayContaining([emilePrivate, emileImported]));
      expect(names.items.map((item) => item.id)).not.toContain(zoeFailed);

      const byEmail = (await (await t.call(`/admin/activities?q=${zoe}@test`, admin)).json()) as AdminActivityListResponse;
      expect(byEmail.items.map((item) => item.id)).toEqual([zoeFailed]);

      expect((await list("")).items).toHaveLength(3);
      const byTitle = (await (await t.call(`/admin/activities?q=VELO%20${tag}`, admin)).json()) as AdminActivityListResponse;
      expect(byTitle.items.map((item) => item.id)).toEqual([zoeFailed]);
    });

    it("is refused to an athlete", async () => {
      const response = await t.call("/admin/activities", emile, { role: "user" });
      expect(response.status).toBe(403);
    });
  });

  describe("detail", () => {
    it("shows official values, the public trace, Media, comments, kudos, import and efforts", async () => {
      const id = await seedActivity({
        userId: emile,
        title: `Détail ${tag}`,
        description: "Belle sortie",
        source: "imported",
      });
      await t.sql(
        `insert into activities.activity_stats (activity_id, distance_m, moving_time_s, elapsed_time_s, elevation_gain_m)
         values ($1, 10012.5, 3000, 3600, 120)`,
        [id],
      );
      await t.sql(
        `insert into activities.activity_track (activity_id, route, location_name)
         values ($1, ST_GeomFromText('LINESTRING(2.35 48.85, 2.36 48.86)', 4326), 'Paris')`,
        [id],
      );
      const mediaId = randomUUID();
      await t.sql(
        `insert into activities.activity_media (id, activity_id, s3_key, kind, width, height)
         values ($1, $2, $3, 'photo', 4000, 3000)`,
        [mediaId, id, activityMediaPrefix(emile, id, mediaId)],
      );
      const commentId = randomUUID();
      await t.sql(
        `insert into engagement.comment (id, activity_id, user_id, body, created_at)
         values ($1, $2, $3, 'Bravo !', '2026-11-02T12:00:00Z'),
                ($4, $2, $3, 'Supprimé', '2026-11-02T12:01:00Z')`,
        [commentId, id, zoe, randomUUID()],
      );
      await t.sql("update engagement.comment set deleted_at = now() where body = 'Supprimé' and activity_id = $1", [id]);
      await t.sql(
        "insert into engagement.kudos (user_id, activity_id, created_at) values ($1, $2, '2026-11-02T13:00:00Z')",
        [zoe, id],
      );
      await t.sql(
        `insert into activities.activity_import (id, user_id, format, original_file_name, size_bytes, status, activity_id)
         values ($1, $2, 'gpx', 'sortie.gpx', 1234, 'imported', $1)`,
        [id, emile],
      );
      const segmentId = randomUUID();
      await t.sql("insert into segments.segment (id, name, sport_type_code) values ($1, 'Côte du Mont', 'run')", [
        segmentId,
      ]);
      const effortId = randomUUID();
      await t.sql(
        `insert into segments.segment_effort (id, activity_id, segment_id, user_id, elapsed_time_s, started_at,
           start_index, end_index, min_distance_to_activity_start_m, min_distance_to_activity_end_m)
         values ($1, $2, $3, $4, 420, '2026-11-02T08:10:00Z', 10, 430, 500, 800)`,
        [effortId, id, segmentId, emile],
      );

      const response = await t.call(`/admin/activities/${id}`, admin);
      expect(response.status).toBe(200);
      const detail = (await response.json()) as AdminActivityDetail;

      expect(detail).toMatchObject({
        id,
        title: `Détail ${tag}`,
        description: "Belle sortie",
        athlete: { id: emile, displayName: "Émile Durand" },
        processingStatus: "processed",
        processingError: null,
        processingAttempts: 2,
        source: "imported",
        stats: { distanceM: 10012.5, movingTimeS: 3000, elevationGainM: 120 },
        route: [
          [2.35, 48.85],
          [2.36, 48.86],
        ],
        locationName: "Paris",
        commentCount: 1,
        comments: [{ id: commentId, body: "Bravo !", author: { id: zoe, displayName: "Zoé Martin" } }],
        kudosCount: 1,
        kudos: [{ athlete: { id: zoe }, createdAt: "2026-11-02T13:00:00.000Z" }],
        import: { id, format: "gpx", fileName: "sortie.gpx", status: "imported" },
        efforts: [{ id: effortId, segmentId, segmentName: "Côte du Mont", elapsedTimeS: 420 }],
      });
      expect(detail.media).toHaveLength(1);
      expect(detail.media[0]).toMatchObject({ id: mediaId, kind: "photo" });
      expect(detail.media[0]!.thumbUrl).toContain(activityMediaPrefix(emile, id, mediaId));
      await t.sql("delete from segments.segment where id = $1", [segmentId]);
    });

    it("shows a failed Activity's error and no trace", async () => {
      const id = await seedActivity({ userId: zoe, status: "failed", error: "invalid_trace" });
      const detail = (await (await t.call(`/admin/activities/${id}`, admin)).json()) as AdminActivityDetail;
      expect(detail).toMatchObject({ processingStatus: "failed", processingError: "invalid_trace", stats: null, route: null });
    });

    it("answers 404 for an unknown Activity", async () => {
      const response = await t.call(`/admin/activities/${randomUUID()}`, admin);
      expect(response.status).toBe(404);
    });
  });

  describe("Retraiter", () => {
    it("sends a failed Activity back to processing, enqueues it and records it", async () => {
      const id = await seedActivity({ userId: zoe, status: "failed", error: "invalid_trace" });

      const response = await t.call(`/admin/activities/${id}/reprocess`, admin, { method: "POST" });

      expect(response.status).toBe(202);
      expect(await response.json()).toEqual({ id, processingStatus: "processing" });
      const [row] = await t.sql<{ processing_status: string; processing_error: string | null }>(
        "select processing_status, processing_error from activities.activity where id = $1",
        [id],
      );
      expect(row).toEqual({ processing_status: "processing", processing_error: null });
      const job = await t.app.get<Queue>(getQueueToken(ACTIVITIES_QUEUE_NAME)).getJob(processActivityJobId(id));
      expect(job?.data).toMatchObject({ activityId: id, userId: zoe });
      expect(await journal("activity.reprocess", id)).toMatchObject([
        { actor_id: admin, target_type: "activity", subject_user_id: zoe, reason: null },
      ]);
      expect(notices).not.toHaveBeenCalled();
    });

    it("answers 409 unless the Activity failed", async () => {
      const id = await seedActivity({ userId: zoe, status: "processed" });

      const response = await t.call(`/admin/activities/${id}/reprocess`, admin, { method: "POST" });

      expect(response.status).toBe(409);
      expect(await errorCode(response)).toBe("not_failed");
      expect(await journal("activity.reprocess", id)).toEqual([]);
    });
  });
});
