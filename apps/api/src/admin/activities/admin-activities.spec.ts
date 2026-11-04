import { randomUUID } from "node:crypto";
import { getQueueToken } from "@nestjs/bullmq";
import { EventEmitter2 } from "@nestjs/event-emitter";
import type { Queue } from "bullmq";
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi, type MockInstance } from "vitest";
import {
  ACTIVITIES_QUEUE_NAME,
  ACTIVITY_DELETED_EVENT,
  ACTIVITY_UPDATED_EVENT,
  COMMENT_DELETED_EVENT,
  MEDIA_DELETED_EVENT,
  activityMediaPrefix,
  activityPrefix,
  processActivityJobId,
  type AdminActivityDetail,
  type AdminActivityListResponse,
  type AuditEntryListResponse,
} from "@repo/contracts";
import { ActivitiesModule } from "@repo/core/activities";
import { EngagementModule } from "@repo/core/engagement";
import { SegmentsModule } from "@repo/core/segments";
import { UsersModule } from "@repo/core/users";
import { AthleteIdentities } from "../../identities/athlete-identities.js";
import { MediaAssembler } from "../../media/media-assembler.js";
import { bootstrapAdminTestApp, type AdminTestApp } from "../../testing/admin-test-app.js";
import { AuditEntriesController } from "../audit/audit-entries.controller.js";
import { AuditEntryAssembler } from "../audit/audit-entry-assembler.js";
import { AdminCommentsController } from "../comments/admin-comments.controller.js";
import { SanctionNotices, type SanctionNotice } from "../sanctions/sanction-notices.js";
import { AdminActivitiesController } from "./admin-activities.controller.js";
import { AdminActivityAssembler } from "./admin-activity-assembler.js";

/**
 * The backoffice Activities screen (ADR-038 §11): list, detail, « Retraiter » and the four
 * Sanctions, over real HTTP, Postgres and Redis (ADR-024 §2).
 */
describe("/v1/admin/activities (integration)", () => {
  let t: AdminTestApp;
  let admin: string;
  let emile: string;
  let zoe: string;
  let emit: MockInstance<EventEmitter2["emit"]>;
  let notices: MockInstance<SanctionNotices["send"]>;
  /** A tag on every seeded title, so the list only sees this file's Activities. */
  const tag = `t${randomUUID().slice(0, 8)}`;

  async function seedActivity(values: {
    userId: string;
    title?: string;
    description?: string | null;
    status?: "pending" | "processing" | "processed" | "failed";
    source?: "recorded" | "imported" | "manual";
    sport?: string;
    visibility?: "public" | "followers" | "private";
    startedAt?: string;
    createdAt?: string;
    error?: string | null;
  }): Promise<string> {
    const id = randomUUID();
    const startedAt = values.startedAt ?? "2026-11-02T08:00:00Z";
    await t.sql(
      `insert into activities.activity
         (id, user_id, sport_type_code, title, description, started_at, ended_at, visibility,
          processing_status, source, processing_error, processing_attempts, created_at, updated_at)
       values ($1, $2, $3, $4, $5, $6, $6::timestamptz + interval '1 hour', $7, $8, $9, $10, 2, $11, $11)`,
      [
        id,
        values.userId,
        values.sport ?? "run",
        values.title ?? `Sortie ${tag}`,
        values.description ?? null,
        startedAt,
        values.visibility ?? "public",
        values.status ?? "processed",
        values.source ?? "recorded",
        values.error ?? null,
        values.createdAt ?? new Date().toISOString(),
      ],
    );
    return id;
  }

  async function list(query: string): Promise<AdminActivityListResponse> {
    const response = await t.call(`/admin/activities?q=${tag}&${query}`, admin);
    expect(response.status).toBe(200);
    return (await response.json()) as AdminActivityListResponse;
  }

  async function journal(action: string, targetId: string) {
    const rows = await t.sql<{
      actor_id: string;
      target_type: string;
      target_id: string;
      subject_user_id: string | null;
      reason: string | null;
      id: string;
    }>("select * from audit.admin_audit_entry where action = $1 and target_id = $2", [action, targetId]);
    return rows;
  }

  const errorCode = async (response: Response) =>
    ((await response.json()) as { error: { code: string } }).error.code;

  beforeAll(async () => {
    t = await bootstrapAdminTestApp({
      imports: [ActivitiesModule, EngagementModule, SegmentsModule, UsersModule],
      controllers: [AdminActivitiesController, AdminCommentsController, AuditEntriesController],
      providers: [AdminActivityAssembler, AthleteIdentities, MediaAssembler, AuditEntryAssembler, SanctionNotices],
    });
    admin = await t.seedUser("Alice Admin", { role: "admin" });
    emile = await t.seedUser("Émile Durand");
    zoe = await t.seedUser("Zoé Martin");
  }, 30_000);

  beforeEach(() => {
    emit = vi.spyOn(t.app.get(EventEmitter2), "emit");
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
        `insert into segments.segment_effort (id, activity_id, segment_id, user_id, elapsed_time_s, started_at, rank)
         values ($1, $2, $3, $4, 420, '2026-11-02T08:10:00Z', 3)`,
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
        efforts: [{ id: effortId, segmentId, segmentName: "Côte du Mont", elapsedTimeS: 420, rank: 3 }],
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

  describe("Supprimer l'Activité", () => {
    it("requires a reason", async () => {
      const id = await seedActivity({ userId: emile });
      const response = await t.call(`/admin/activities/${id}`, admin, { method: "DELETE", body: {} });
      expect(response.status).toBe(400);
      expect(await errorCode(response)).toBe("reason_required");
    });

    it("deletes it for good with its files, as a Sanction", async () => {
      const id = await seedActivity({ userId: emile, title: "Sortie du dimanche", startedAt: "2026-11-02T08:00:00Z" });
      const traceKey = `${activityPrefix(emile, id)}trace.json.gz`;
      t.storage.objects.set(traceKey, new Uint8Array([1]));

      const response = await t.call(`/admin/activities/${id}`, admin, {
        method: "DELETE",
        body: { reason: "Contenu choquant" },
      });

      expect(response.status).toBe(204);
      expect(await t.sql("select id from activities.activity where id = $1", [id])).toEqual([]);
      expect(t.storage.objects.has(traceKey)).toBe(false);
      expect(emit).toHaveBeenCalledWith(ACTIVITY_DELETED_EVENT, { activityId: id, userId: emile, bySanction: true });
      const [entry] = await journal("activity.delete", id);
      expect(entry).toMatchObject({ actor_id: admin, subject_user_id: emile, reason: "Contenu choquant" });
      expect(notices).toHaveBeenCalledWith({
        auditEntryId: entry!.id,
        action: "activity.delete",
        athleteId: emile,
        reason: "Contenu choquant",
        activity: { title: "Sortie du dimanche", startedAt: "2026-11-02T08:00:00.000Z" },
        comment: null,
      });
    });

    it("answers 409 while it is processing", async () => {
      const id = await seedActivity({ userId: emile, status: "processing" });
      const response = await t.call(`/admin/activities/${id}`, admin, { method: "DELETE", body: { reason: "Spam" } });
      expect(response.status).toBe(409);
      expect(await errorCode(response)).toBe("not_deletable");
      expect(await journal("activity.delete", id)).toEqual([]);
    });

    it("answers 404 for an unknown Activity", async () => {
      const response = await t.call(`/admin/activities/${randomUUID()}`, admin, {
        method: "DELETE",
        body: { reason: "Spam" },
      });
      expect(response.status).toBe(404);
    });
  });

  describe("Retirer un Média", () => {
    it("removes the Media and its files, as a Sanction", async () => {
      const id = await seedActivity({ userId: emile, title: "Rando", startedAt: "2026-11-02T08:00:00Z" });
      const mediaId = randomUUID();
      await t.sql(
        `insert into activities.activity_media (id, activity_id, s3_key, kind, width, height)
         values ($1, $2, $3, 'photo', 100, 100)`,
        [mediaId, id, activityMediaPrefix(emile, id, mediaId)],
      );
      const fileKey = `${activityMediaPrefix(emile, id, mediaId)}original.jpg`;
      t.storage.objects.set(fileKey, new Uint8Array([1]));

      const response = await t.call(`/admin/activities/${id}/media/${mediaId}`, admin, {
        method: "DELETE",
        body: { reason: "Photo inappropriée" },
      });

      expect(response.status).toBe(204);
      expect(await t.sql("select id from activities.activity_media where id = $1", [mediaId])).toEqual([]);
      expect(t.storage.objects.has(fileKey)).toBe(false);
      expect(emit).toHaveBeenCalledWith(MEDIA_DELETED_EVENT, {
        mediaId,
        activityId: id,
        userId: emile,
        bySanction: true,
      });
      const [entry] = await journal("media.remove", mediaId);
      expect(entry).toMatchObject({ target_type: "media", subject_user_id: emile, reason: "Photo inappropriée" });
      expect(notices).toHaveBeenCalledWith(
        expect.objectContaining({
          auditEntryId: entry!.id,
          action: "media.remove",
          athleteId: emile,
          activity: { title: "Rando", startedAt: "2026-11-02T08:00:00.000Z" },
        }),
      );
    });

    it("answers 404 for a Media of another Activity", async () => {
      const id = await seedActivity({ userId: emile });
      const response = await t.call(`/admin/activities/${id}/media/${randomUUID()}`, admin, {
        method: "DELETE",
        body: { reason: "Spam" },
      });
      expect(response.status).toBe(404);
      expect(await errorCode(response)).toBe("media_not_found");
    });
  });

  describe("Réinitialiser titre et description", () => {
    it("puts back the default title and empties the description, as a Sanction", async () => {
      // 08:00 UTC is 09:00 in Paris: a morning run.
      const id = await seedActivity({
        userId: emile,
        title: "Titre insultant",
        description: "Description insultante",
        startedAt: "2026-11-02T08:00:00Z",
      });

      const response = await t.call(`/admin/activities/${id}/reset-text`, admin, {
        method: "POST",
        body: { reason: "Propos haineux" },
      });

      expect(response.status).toBe(200);
      expect(await response.json()).toEqual({ id, title: "Course à pied le matin", description: null });
      expect(emit).toHaveBeenCalledWith(ACTIVITY_UPDATED_EVENT, {
        activityId: id,
        userId: emile,
        changedFields: ["title", "description"],
      });
      const [entry] = await journal("activity.text.reset", id);
      expect(entry).toMatchObject({ subject_user_id: emile, reason: "Propos haineux" });
      // The e-mail names the Activity as the athlete knew it.
      expect(notices).toHaveBeenCalledWith(
        expect.objectContaining({
          action: "activity.text.reset",
          activity: { title: "Titre insultant", startedAt: "2026-11-02T08:00:00.000Z" },
        }),
      );
    });

    it("requires a reason", async () => {
      const id = await seedActivity({ userId: emile });
      const response = await t.call(`/admin/activities/${id}/reset-text`, admin, { method: "POST", body: {} });
      expect(response.status).toBe(400);
    });
  });

  describe("Retirer un commentaire", () => {
    it("soft deletes the comment, as a Sanction, and the Journal no longer links it", async () => {
      const id = await seedActivity({ userId: emile, title: "Sortie longue", startedAt: "2026-11-02T08:00:00Z" });
      const commentId = randomUUID();
      await t.sql("insert into engagement.comment (id, activity_id, user_id, body) values ($1, $2, $3, $4)", [
        commentId,
        id,
        zoe,
        "Commentaire haineux",
      ]);

      const response = await t.call(`/admin/comments/${commentId}`, admin, {
        method: "DELETE",
        body: { reason: "Harcèlement" },
      });

      expect(response.status).toBe(204);
      const [row] = await t.sql<{ deleted_at: Date | null }>("select deleted_at from engagement.comment where id = $1", [
        commentId,
      ]);
      expect(row!.deleted_at).not.toBeNull();
      expect(emit).toHaveBeenCalledWith(COMMENT_DELETED_EVENT, {
        commentId,
        activityId: id,
        userId: admin,
        authorId: zoe,
        bySanction: true,
      });
      const [entry] = await journal("comment.remove", commentId);
      expect(entry).toMatchObject({ target_type: "comment", subject_user_id: zoe, reason: "Harcèlement" });
      expect(notices).toHaveBeenCalledWith({
        auditEntryId: entry!.id,
        action: "comment.remove",
        athleteId: zoe,
        reason: "Harcèlement",
        activity: { title: "Sortie longue", startedAt: "2026-11-02T08:00:00.000Z" },
        comment: { body: "Commentaire haineux" },
      });

      const journalPage = (await (
        await t.call(`/admin/audit-entries?action=comment.remove&subjectUserId=${zoe}`, admin)
      ).json()) as AuditEntryListResponse;
      expect(journalPage.items[0]!.target).toEqual({ type: "comment", id: commentId, exists: false });
    });

    it("answers 404 for a comment already removed", async () => {
      const id = await seedActivity({ userId: emile });
      const commentId = randomUUID();
      await t.sql(
        "insert into engagement.comment (id, activity_id, user_id, body, deleted_at) values ($1, $2, $3, 'x', now())",
        [commentId, id, zoe],
      );
      const response = await t.call(`/admin/comments/${commentId}`, admin, {
        method: "DELETE",
        body: { reason: "Spam" },
      });
      expect(response.status).toBe(404);
      expect(await journal("comment.remove", commentId)).toEqual([]);
    });
  });

  describe("Journal target links", () => {
    it("links a Media and a comment while they exist", async () => {
      const id = await seedActivity({ userId: emile });
      const mediaId = randomUUID();
      await t.sql(
        `insert into activities.activity_media (id, activity_id, s3_key, kind, width, height)
         values ($1, $2, $3, 'photo', 100, 100)`,
        [mediaId, id, activityMediaPrefix(emile, id, mediaId)],
      );
      const commentId = randomUUID();
      await t.sql("insert into engagement.comment (id, activity_id, user_id, body) values ($1, $2, $3, 'ok')", [
        commentId,
        id,
        zoe,
      ]);
      for (const [action, type, target] of [
        ["media.remove", "media", mediaId],
        ["comment.remove", "comment", commentId],
      ] as const) {
        await t.sql(
          `insert into audit.admin_audit_entry (id, actor_id, action, target_type, target_id, subject_user_id, request_id)
           values ($1, $2, $3, $4, $5, $6, 'req-links')`,
          [randomUUID(), admin, action, type, target, emile],
        );
      }

      const page = (await (
        await t.call(`/admin/audit-entries?subjectUserId=${emile}&pageSize=100`, admin)
      ).json()) as AuditEntryListResponse;
      const linked = page.items.filter((item) => item.requestId === "req-links").map((item) => item.target);
      expect(linked).toEqual(
        expect.arrayContaining([
          { type: "media", id: mediaId, exists: true },
          { type: "comment", id: commentId, exists: true },
        ]),
      );
    });
  });
});
