import { randomUUID } from "node:crypto";
import { EventEmitter2 } from "@nestjs/event-emitter";
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi, type MockInstance } from "vitest";
import {
  ACTIVITY_DELETED_EVENT,
  ACTIVITY_UPDATED_EVENT,
  COMMENT_DELETED_EVENT,
  MEDIA_DELETED_EVENT,
  activityMediaPrefix,
  activityPrefix,
  type AuditEntryListResponse,
} from "@repo/contracts";
import type { AdminTestApp } from "../../testing/admin-test-app.js";
import { SanctionNotices } from "../sanctions/sanction-notices.js";
import { bootstrapAdminActivities, errorCode, type AdminActivitiesFixture } from "./admin-activities.fixture.js";

/**
 * The Sanctions of the backoffice Activities screen (ADR-038 §11): delete the Activity, remove a
 * Media, reset the texts, remove a comment; and the Journal's links to their targets.
 */
describe("/v1/admin/activities Sanctions (integration)", () => {
  let t: AdminTestApp;
  let admin: string;
  let emile: string;
  let zoe: string;
  let seedActivity: AdminActivitiesFixture["seedActivity"];
  let journal: AdminActivitiesFixture["journal"];
  let emit: MockInstance<EventEmitter2["emit"]>;
  let notices: MockInstance<SanctionNotices["send"]>;

  beforeAll(async () => {
    ({ t, admin, emile, zoe, seedActivity, journal } = await bootstrapAdminActivities());
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
        comment: { body: "Commentaire haineux", postedAt: expect.any(String) },
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
