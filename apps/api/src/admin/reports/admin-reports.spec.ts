import { randomUUID } from "node:crypto";
import { getQueueToken } from "@nestjs/bullmq";
import { EventEmitter2 } from "@nestjs/event-emitter";
import type { Queue } from "bullmq";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import {
  ACCOUNT_DELETED_EVENT,
  ACTIVITY_DELETED_EVENT,
  COMMENT_DELETED_EVENT,
  EMAILS_QUEUE_NAME,
  type AccountDeletedEvent,
  type ActivityDeletedEvent,
  type AdminReportCaseCloseResponse,
  type AdminReportCaseDetail,
  type AdminReportCaseListResponse,
  type AuditEntryListResponse,
  type CommentDeletedEvent,
  type ReportReason,
  type ReportSnapshot,
  type ReportTargetType,
  type SendEmailJob,
} from "@repo/contracts";
import { AuditService } from "@repo/core/audit";
import type { ModerationService } from "@repo/core/moderation";
import type { AdminTestApp } from "../../testing/admin-test-app.js";
import { useExclusiveTestDatabase } from "../../testing/exclusive-test-database.js";

/**
 * The moderation queue (ADR-038 §10): list, detail, « Clore » as « Sanctionné » or « Rejeter »,
 * automatic close when the target disappears, the Administrators' e-mail on a new case, and the
 * Journal's link to a case. Real Postgres and Redis on a database of its own (list totals); the
 * sessions and the accounts come from a fake `AuthService` reading the `user` table.
 */
describe("/v1/admin/reports (integration)", () => {
  let t: AdminTestApp;
  let moderation: ModerationService;
  let events: EventEmitter2;
  let admin: string;
  let otherAdmin: string;

  const json = async <T,>(response: Response, status = 200): Promise<T> => {
    expect(response.status, await response.clone().text()).toBe(status);
    return (await response.json()) as T;
  };
  const errorCode = async (response: Response) => ((await response.json()) as { error: { code: string } }).error.code;
  const get = async <T,>(path: string) => json<T>(await t.call(path, admin));
  const close = (caseId: string, outcome: "resolve" | "dismiss", body: unknown = {}) =>
    t.call(`/admin/reports/${caseId}/${outcome}`, admin, { method: "POST", body });
  /** Polls until `check` passes (listeners run asynchronously). */
  async function eventually(check: () => Promise<void>, timeoutMs = 5_000): Promise<void> {
    const start = Date.now();
    for (;;) {
      try {
        await check();
        return;
      } catch (error) {
        if (Date.now() - start > timeoutMs) {
          throw error;
        }
        await new Promise((resolve) => setTimeout(resolve, 50));
      }
    }
  }

  async function athlete(firstName: string, options: { bio?: string; role?: "admin" | "user" } = {}): Promise<string> {
    const id = await t.seedUser(`${firstName} Test`, { role: options.role });
    await t.sql("insert into users.user_profile (user_id, first_name, last_name, bio) values ($1, $2, 'Test', $3)", [
      id,
      firstName,
      options.bio ?? null,
    ]);
    return id;
  }

  async function activity(userId: string, title = "Sortie du dimanche", description: string | null = null) {
    const id = randomUUID();
    await t.sql(
      `insert into activities.activity (id, user_id, sport_type_code, title, description, started_at, ended_at, processing_status)
       values ($1, $2, 'run', $3, $4, now() - interval '2 hours', now() - interval '1 hour', 'processed')`,
      [id, userId, title, description],
    );
    return id;
  }

  async function comment(userId: string, activityId: string, body: string) {
    const [row] = await t.sql<{ id: string }>(
      "insert into engagement.comment (user_id, activity_id, body) values ($1, $2, $3) returning id",
      [userId, activityId, body],
    );
    return row!.id;
  }

  async function report(
    reporterId: string,
    target: { type: ReportTargetType; id: string; authorId: string; snapshot: ReportSnapshot },
    reason: ReportReason = "spam",
    note?: string,
  ): Promise<string> {
    const outcome = await moderation.report({
      reporterId,
      targetType: target.type,
      targetId: target.id,
      targetUserId: target.authorId,
      reason,
      note,
      snapshot: target.snapshot,
    });
    return outcome.caseId;
  }

  /** A comment by a new author, reported once; returns everything a test needs. */
  async function reportedComment(body = "Texte injurieux", reason: ReportReason = "harassment", note?: string) {
    const author = await athlete("Auteur");
    const reporter = await athlete("Rita");
    const activityId = await activity(author);
    const commentId = await comment(author, activityId, body);
    const caseId = await report(
      reporter,
      { type: "comment", id: commentId, authorId: author, snapshot: { body, activityId } },
      reason,
      note,
    );
    return { author, reporter, activityId, commentId, caseId };
  }

  async function openedAt(caseId: string, iso: string) {
    await t.sql("update moderation.report_case set opened_at = $2 where id = $1", [caseId, iso]);
  }

  beforeAll(async () => {
    await useExclusiveTestDatabase("admin_reports");
    const { bootstrapAdminTestApp } = await import("../../testing/admin-test-app.js");
    const { ActivitiesModule } = await import("@repo/core/activities");
    const { activeBan } = await import("@repo/core/auth");
    const { EngagementModule } = await import("@repo/core/engagement");
    const { ModerationModule, ModerationService: Moderation } = await import("@repo/core/moderation");
    const { EmailJobsModule } = await import("@repo/core/notifications");
    const { UsersModule } = await import("@repo/core/users");
    const { AthleteIdentities } = await import("../../identities/athlete-identities.js");
    const { MediaAssembler } = await import("../../media/media-assembler.js");
    const { AuditEntriesController } = await import("../audit/audit-entries.controller.js");
    const { AuditEntryAssembler } = await import("../audit/audit-entry-assembler.js");
    const { AdminCommentsController } = await import("../comments/admin-comments.controller.js");
    const { SanctionNotices } = await import("../sanctions/sanction-notices.js");
    const { AdminReportsController } = await import("./admin-reports.controller.js");
    const { AdminReportAssembler } = await import("./admin-report-assembler.js");
    const { ReportCaseAlerts } = await import("./report-case-alerts.listener.js");

    const account = async (userId: string) => {
      const [row] = await t.sql<{
        id: string;
        email: string;
        name: string;
        role: "admin" | "user";
        banned: boolean | null;
        banReason: string | null;
        banExpires: Date | null;
        createdAt: Date;
      }>(
        `select id, email, name, role, banned, ban_reason as "banReason", ban_expires as "banExpires", created_at as "createdAt"
         from "user" where id = $1`,
        [userId],
      );
      if (!row) {
        const { NotFoundException } = await import("@nestjs/common");
        throw new NotFoundException({ code: "user_not_found", message: "User not found" });
      }
      return { ...row, twoFactorEnabled: false, signInMethods: [], ban: activeBan(row, new Date()) };
    };

    t = await bootstrapAdminTestApp({
      imports: [ActivitiesModule, EngagementModule, ModerationModule, UsersModule, EmailJobsModule],
      controllers: [AdminReportsController, AdminCommentsController, AuditEntriesController],
      providers: [AthleteIdentities, MediaAssembler, AdminReportAssembler, ReportCaseAlerts, SanctionNotices, AuditEntryAssembler],
      authService: {
        getAccountForAdmin: account,
        listAdminRecipients: () =>
          t.sql('select id as "userId", email from "user" where role = \'admin\' order by id'),
      },
    });
    moderation = t.app.get(Moderation);
    events = t.app.get(EventEmitter2);
    admin = await t.seedUser("Alice Admin", { role: "admin" });
    otherAdmin = await t.seedUser("Bob Admin", { role: "admin" });
  }, 60_000);

  afterAll(async () => {
    await t?.close();
  });

  it("is for Administrators only", async () => {
    expect((await t.call("/admin/reports", admin, { role: "user" })).status).toBe(403);
  });

  describe("GET /v1/admin/reports", () => {
    it("lists open cases oldest first, then the most reported, with preview, author, count and reasons", async () => {
      const older = await reportedComment("Premier commentaire injurieux", "harassment");
      const author = await athlete("Paul", { bio: "Bio douteuse" });
      const [r1, r2] = [await athlete("Un"), await athlete("Deux")];
      const athleteCase = await report(
        r1,
        { type: "athlete", id: author, authorId: author, snapshot: { name: "Paul Test", bio: "Bio douteuse", avatarKey: null } },
        "impersonation",
      );
      await report(
        r2,
        { type: "athlete", id: author, authorId: author, snapshot: { name: "Paul Test", bio: null, avatarKey: null } },
        "spam",
      );
      const same = await reportedComment("Même âge", "spam");
      await openedAt(older.caseId, "2030-01-01T08:00:00Z");
      await openedAt(athleteCase, "2030-01-02T08:00:00Z");
      await openedAt(same.caseId, "2030-01-02T08:00:00Z");

      const page = await get<AdminReportCaseListResponse>("/admin/reports?from=2030-01-01&to=2030-01-02");

      expect(page.total).toBe(3);
      expect(page.items.map((item) => item.id)).toEqual([older.caseId, athleteCase, same.caseId]);
      expect(page.items[0]).toMatchObject({
        targetType: "comment",
        targetId: older.commentId,
        status: "open",
        openedAt: "2030-01-01T08:00:00.000Z",
        closedAt: null,
        author: { id: older.author, displayName: "Auteur Test" },
        preview: "Premier commentaire injurieux",
        reportCount: 1,
        reasons: ["harassment"],
      });
      expect(page.items[1]).toMatchObject({
        targetType: "athlete",
        preview: "Paul Test",
        reportCount: 2,
        reasons: ["spam", "impersonation"],
      });
    });

    it("filters by target type, reason and opening period; « Clos » lists the closed cases", async () => {
      const commentCase = await reportedComment("Filtré", "sexual_or_violent");
      await openedAt(commentCase.caseId, "2030-02-01T08:00:00Z");
      const dismissed = await reportedComment("Rejeté", "sexual_or_violent");
      await openedAt(dismissed.caseId, "2030-02-01T09:00:00Z");
      await json(await close(dismissed.caseId, "dismiss"));

      const byReason = await get<AdminReportCaseListResponse>(
        "/admin/reports?reason=sexual_or_violent&targetType=comment&from=2030-02-01&to=2030-02-01",
      );
      expect(byReason.items.map((item) => item.id)).toEqual([commentCase.caseId]);
      const none = await get<AdminReportCaseListResponse>("/admin/reports?targetType=activity&from=2030-02-01&to=2030-02-01");
      expect(none.total).toBe(0);

      const closed = await get<AdminReportCaseListResponse>("/admin/reports?state=closed&from=2030-02-01&to=2030-02-01");
      expect(closed.items).toHaveLength(1);
      expect(closed.items[0]).toMatchObject({ id: dismissed.caseId, status: "dismissed", preview: null, reportCount: 1 });
      expect(closed.items[0]!.closedAt).not.toBeNull();
    });
  });

  describe("GET /v1/admin/reports/:caseId", () => {
    it("shows the current comment with its Activity, the Reports with their copy, and the author", async () => {
      const { caseId, commentId, activityId, author, reporter } = await reportedComment("Texte d'origine", "other", "Insultant");
      await t.sql("update engagement.comment set body = 'Texte modifié', updated_at = now() where id = $1", [commentId]);
      await t.sql("delete from \"user\" where id = $1", [reporter]);
      await t.sql("update \"user\" set banned = true, ban_reason = 'x' where id = $1", [author]);

      const detail = await get<AdminReportCaseDetail>(`/admin/reports/${caseId}`);

      expect(detail).toMatchObject({
        id: caseId,
        targetType: "comment",
        targetId: commentId,
        status: "open",
        closedBy: null,
        closeNote: null,
        canResolve: false,
        current: { kind: "comment", body: "Texte modifié", activity: { id: activityId, title: "Sortie du dimanche" } },
        author: { id: author, displayName: "Auteur Test", role: "user", banned: true, reportsReceived: 1, pastSanctions: 0 },
      });
      expect(detail.reports).toEqual([
        expect.objectContaining({
          reporter: null,
          reason: "other",
          note: "Insultant",
          copy: { kind: "comment", body: "Texte d'origine" },
          changedSince: true,
        }),
      ]);
    });

    it("shows an Activity with its Media, and an athlete with name and bio; unchanged copies are not flagged", async () => {
      const author = await athlete("Lou", { bio: "Ma bio" });
      const reporter = await athlete("Rita");
      const activityId = await activity(author, "Titre", "Description");
      const activityCase = await report(reporter, {
        type: "activity",
        id: activityId,
        authorId: author,
        snapshot: { title: "Titre", description: "Description", mediaIds: [] },
      });
      const athleteCase = await report(reporter, {
        type: "athlete",
        id: author,
        authorId: author,
        snapshot: { name: "Lou Test", bio: "Ma bio", avatarKey: null },
      });

      const activityDetail = await get<AdminReportCaseDetail>(`/admin/reports/${activityCase}`);
      expect(activityDetail.current).toMatchObject({ kind: "activity", title: "Titre", description: "Description", media: [] });
      expect(activityDetail.reports[0]).toMatchObject({
        reporter: { id: reporter, displayName: "Rita Test" },
        copy: { kind: "activity", title: "Titre", description: "Description", mediaCount: 0 },
        changedSince: false,
      });
      const athleteDetail = await get<AdminReportCaseDetail>(`/admin/reports/${athleteCase}`);
      expect(athleteDetail.current).toMatchObject({ kind: "athlete", displayName: "Lou Test", bio: "Ma bio" });
      expect(athleteDetail.reports[0]).toMatchObject({ copy: { kind: "athlete", name: "Lou Test", bio: "Ma bio" }, changedSince: false });
      expect(athleteDetail.author.reportsReceived).toBe(2);
    });

    it("answers 404 for an unknown case", async () => {
      const response = await t.call(`/admin/reports/${randomUUID()}`, admin);
      expect(response.status).toBe(404);
      expect(await errorCode(response)).toBe("report_case_not_found");
    });
  });

  describe("« Clore »", () => {
    it("« Rejeter »: closes every Report, erases the copies, keeps the notes, and goes to the Journal", async () => {
      const { caseId } = await reportedComment("À rejeter", "other", "Note du signaleur");

      const closed = await json<AdminReportCaseCloseResponse>(await close(caseId, "dismiss", { note: " Pas de problème " }));

      expect(closed).toMatchObject({ id: caseId, status: "dismissed", count: 1 });
      const detail = await get<AdminReportCaseDetail>(`/admin/reports/${caseId}`);
      expect(detail).toMatchObject({ status: "dismissed", closedBy: { id: admin, displayName: "Alice Admin" }, closeNote: "Pas de problème" });
      expect(detail.reports[0]).toMatchObject({ note: "Note du signaleur", copy: null });
      const [entry] = await t.sql<{ action: string; actor_id: string; target_type: string; reason: string; details: unknown }>(
        "select * from audit.admin_audit_entry where target_id = $1",
        [caseId],
      );
      expect(entry).toMatchObject({
        action: "report.dismiss",
        actor_id: admin,
        target_type: "report_case",
        reason: "Pas de problème",
        details: { count: 1 },
      });
    });

    it("answers 409 case_closed once closed", async () => {
      const { caseId } = await reportedComment();
      await json(await close(caseId, "dismiss"));

      const again = await close(caseId, "resolve");
      expect(again.status).toBe(409);
      expect(await errorCode(again)).toBe("case_closed");
    });

    it("« Sanctionné » needs a Sanction in the Journal since the opening, on the target or its author", async () => {
      const { caseId, author } = await reportedComment();
      const audit = t.app.get(AuditService);
      // Before the opening: does not count.
      await audit.record({ actorId: admin, action: "user.ban", targetId: author, subjectUserId: author, reason: "x" });
      await t.sql("update audit.admin_audit_entry set created_at = now() - interval '1 day' where subject_user_id = $1", [author]);

      const refused = await close(caseId, "resolve");
      expect(refused.status).toBe(409);
      expect(await errorCode(refused)).toBe("no_sanction");

      await audit.record({ actorId: admin, action: "user.ban", targetId: author, subjectUserId: author, reason: "Ban" });
      const detail = await get<AdminReportCaseDetail>(`/admin/reports/${caseId}`);
      expect(detail.canResolve).toBe(true);
      expect(detail.author.pastSanctions).toBe(2);

      const closed = await json<AdminReportCaseCloseResponse>(await close(caseId, "resolve"));
      expect(closed.status).toBe("actioned");
      const [entry] = await t.sql<{ action: string }>("select action from audit.admin_audit_entry where target_id = $1", [caseId]);
      expect(entry!.action).toBe("report.resolve");
    });
  });

  describe("automatic close when the target disappears (author « Système »)", () => {
    const statusOf = async (caseId: string) => (await get<AdminReportCaseDetail>(`/admin/reports/${caseId}`));

    it("removing the comment as a Sanction closes its case as « Sanctionné »", async () => {
      const { caseId, commentId } = await reportedComment();

      expect((await t.call(`/admin/comments/${commentId}`, admin, { method: "DELETE", body: { reason: "Insulte" } })).status).toBe(204);

      await eventually(async () => {
        const detail = await statusOf(caseId);
        expect(detail).toMatchObject({ status: "actioned", closedBy: null, current: null });
        expect(detail.reports[0]!.copy).toBeNull();
      });
    });

    it("a comment deleted by its author closes as « Cible supprimée »", async () => {
      const { caseId, commentId, activityId, author } = await reportedComment();
      await t.sql("update engagement.comment set deleted_at = now() where id = $1", [commentId]);
      const event: CommentDeletedEvent = { commentId, activityId, userId: author, authorId: author, bySanction: false };
      events.emit(COMMENT_DELETED_EVENT, event);

      await eventually(async () => expect((await statusOf(caseId)).status).toBe("target_gone"));
    });

    it("a deleted Activity closes its case, and the cases of its comments", async () => {
      const { caseId: commentCase, activityId, author } = await reportedComment();
      const reporter = await athlete("Rita");
      const activityCase = await report(reporter, {
        type: "activity",
        id: activityId,
        authorId: author,
        snapshot: { title: "Sortie du dimanche", description: null, mediaIds: [] },
      });
      await t.sql("delete from activities.activity where id = $1", [activityId]);
      const event: ActivityDeletedEvent = { activityId, userId: author, bySanction: true };
      events.emit(ACTIVITY_DELETED_EVENT, event);

      await eventually(async () => {
        expect((await statusOf(activityCase)).status).toBe("actioned");
        expect((await statusOf(commentCase)).status).toBe("target_gone");
      });
    });

    it("a deleted account closes every case on the athlete or their content", async () => {
      const { caseId: commentCase, author } = await reportedComment();
      const reporter = await athlete("Rita");
      const athleteCase = await report(reporter, {
        type: "athlete",
        id: author,
        authorId: author,
        snapshot: { name: "Auteur Test", bio: null, avatarKey: null },
      });
      const unrelated = await reportedComment();
      await t.sql('delete from "user" where id = $1', [author]);
      const event: AccountDeletedEvent = { userId: author, bySanction: true };
      events.emit(ACCOUNT_DELETED_EVENT, event);

      await eventually(async () => {
        const detail = await statusOf(athleteCase);
        expect(detail).toMatchObject({ status: "actioned", author: { id: author, displayName: null, role: null } });
        expect((await statusOf(commentCase)).status).toBe("actioned");
      });
      expect((await statusOf(unrelated.caseId)).status).toBe("open");
    });
  });

  it("e-mails every Administrator when a case opens, never on a later Report", async () => {
    const queue = t.app.get<Queue>(getQueueToken(EMAILS_QUEUE_NAME));
    const jobsOf = async (caseId: string) =>
      (await queue.getJobs(["waiting", "delayed", "active", "completed", "failed"]))
        .map((job) => job.data as SendEmailJob)
        .filter((job) => job.template === "report-case-opened" && job.data.caseUrl.endsWith(`/reports/${caseId}`));

    const { caseId, commentId, author } = await reportedComment("Spam", "spam");
    await eventually(async () => expect(await jobsOf(caseId)).toHaveLength(2));
    const jobs = await jobsOf(caseId);
    expect(jobs.map((job) => job.to).sort()).toEqual([`${admin}@test.local`, `${otherAdmin}@test.local`].sort());
    expect(jobs[0]).toMatchObject({ userId: null, data: { targetType: "comment", reason: "spam" } });

    const second = await athlete("Second");
    await report(second, { type: "comment", id: commentId, authorId: author, snapshot: { body: "Spam", activityId: randomUUID() } });
    await new Promise((resolve) => setTimeout(resolve, 200));
    expect(await jobsOf(caseId)).toHaveLength(2);
  });

  it("the Journal links a closing to its case", async () => {
    const { caseId } = await reportedComment();
    await json(await close(caseId, "dismiss"));

    const journal = await get<AuditEntryListResponse>("/admin/audit-entries?action=report.dismiss");
    expect(journal.items.find((entry) => entry.target.id === caseId)?.target).toEqual({
      type: "report_case",
      id: caseId,
      exists: true,
    });
  });
});
