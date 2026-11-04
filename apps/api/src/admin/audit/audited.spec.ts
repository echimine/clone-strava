import { randomUUID } from "node:crypto";
import { Body, Controller, HttpCode, NotFoundException, Param, Post, UseGuards } from "@nestjs/common";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { ActivitiesModule } from "@repo/core/activities";
import { AuditService } from "@repo/core/audit";
import { AdminGuard } from "../../auth/admin.guard.js";
import { SessionGuard } from "../../auth/session.guard.js";
import { bootstrapAdminTestApp, type AdminTestApp } from "../../testing/admin-test-app.js";
import { AdminActivityImportsController } from "../activity-imports/admin-activity-imports.controller.js";
import { Audited, CurrentAuditDraft, type AuditDraft } from "./audited.decorator.js";

/** Stand-in admin routes, one per way of declaring the audit (ADR-038 §3). */
@Controller("admin/audit-probe")
@UseGuards(SessionGuard, AdminGuard)
class AuditProbeController {
  @Post("users/:id/ban")
  @HttpCode(200)
  @Audited("user.ban", { reason: "required" })
  ban(@Param("id") id: string, @Body() body: { duration?: string }, @CurrentAuditDraft() draft: AuditDraft) {
    draft.details = { duration: body.duration };
    return { banned: id, entryId: draft.entryId };
  }

  @Post("reports/:caseId/resolve")
  @HttpCode(200)
  @Audited("report.resolve", { reason: "optional", targetParam: "caseId" })
  resolve(@Param("caseId") caseId: string, @CurrentAuditDraft() draft: AuditDraft) {
    draft.subjectUserId = SUBJECT;
    return { resolved: caseId };
  }

  @Post("queues/:name/pause")
  @HttpCode(200)
  @Audited("queue.pause", { reason: "none", targetParam: "name" })
  pause(@Param("name") name: string, @Body() body: { reason?: string }) {
    return { paused: name, ignored: body.reason };
  }

  @Post("comments/:id/remove")
  @Audited("comment.remove", { reason: "required" })
  remove(): never {
    throw new NotFoundException({ code: "comment_not_found", message: "Comment not found" });
  }
}

const SUBJECT = randomUUID();

type Entry = {
  actor_id: string | null;
  action: string;
  target_type: string;
  target_id: string | null;
  subject_user_id: string | null;
  reason: string | null;
  details: Record<string, unknown> | null;
  request_id: string | null;
};

describe("@Audited admin writes (ADR-038 §3, integration)", () => {
  let t: AdminTestApp;
  let admin: string;

  /** The entries `admin` authored, newest first. */
  const entriesBy = (actorId: string) =>
    t.sql<Entry & { id: string }>(
      "select * from audit.admin_audit_entry where actor_id = $1 order by created_at desc",
      [actorId],
    );

  beforeAll(async () => {
    t = await bootstrapAdminTestApp({
      imports: [ActivitiesModule],
      controllers: [AuditProbeController, AdminActivityImportsController],
    });
    admin = await t.seedUser("Admin Audit", { role: "admin" });
  }, 30_000);

  afterAll(async () => {
    await t?.close();
  });

  it("records a Sanction after success: author, target from the route, reason, details, request id", async () => {
    const target = randomUUID();
    const response = await t.call(`/admin/audit-probe/users/${target}/ban`, admin, {
      method: "POST",
      body: { duration: "7d", reason: "  Propos haineux  " },
      requestId: "req-ban-1",
    });

    expect(response.status).toBe(200);
    const { entryId } = (await response.json()) as { entryId: string };
    const [entry] = await entriesBy(admin);
    expect(entry).toMatchObject({
      id: entryId,
      actor_id: admin,
      action: "user.ban",
      target_type: "user",
      target_id: target,
      // A user target is the athlete concerned unless the handler says otherwise.
      subject_user_id: target,
      reason: "Propos haineux",
      details: { duration: "7d" },
      request_id: "req-ban-1",
    });
  });

  it("refuses a Sanction without a reason with 400, and records nothing", async () => {
    const before = (await entriesBy(admin)).length;
    for (const body of [{}, { reason: "   " }]) {
      const response = await t.call(`/admin/audit-probe/users/${randomUUID()}/ban`, admin, { method: "POST", body });
      expect(response.status).toBe(400);
      expect(((await response.json()) as { error: { code: string } }).error.code).toBe("reason_required");
    }
    expect(await entriesBy(admin)).toHaveLength(before);
  });

  it("takes the target from the named route parameter, and the subject from the handler", async () => {
    const caseId = randomUUID();
    const response = await t.call(`/admin/audit-probe/reports/${caseId}/resolve`, admin, { method: "POST", body: {} });

    expect(response.status).toBe(200);
    const [entry] = await entriesBy(admin);
    expect(entry).toMatchObject({
      action: "report.resolve",
      target_type: "report_case",
      target_id: caseId,
      subject_user_id: SUBJECT,
      reason: null,
    });
  });

  it("keeps no reason for a route that takes none", async () => {
    const response = await t.call("/admin/audit-probe/queues/activities/pause", admin, {
      method: "POST",
      body: { reason: "ignored" },
    });

    expect(response.status).toBe(200);
    const [entry] = await entriesBy(admin);
    expect(entry).toMatchObject({ action: "queue.pause", target_type: "queue", target_id: "activities", reason: null });
  });

  it("records nothing when the action fails", async () => {
    const before = (await entriesBy(admin)).length;
    const response = await t.call(`/admin/audit-probe/comments/${randomUUID()}/remove`, admin, {
      method: "POST",
      body: { reason: "Spam" },
    });

    expect(response.status).toBe(404);
    expect(await entriesBy(admin)).toHaveLength(before);
  });

  it("keeps the action done when the Journal cannot be written", async () => {
    const audit = t.app.get(AuditService);
    const spy = vi.spyOn(audit, "record").mockRejectedValueOnce(new Error("database down"));

    const response = await t.call(`/admin/audit-probe/users/${randomUUID()}/ban`, admin, {
      method: "POST",
      body: { reason: "Spam" },
    });

    expect(response.status).toBe(200);
    expect(spy).toHaveBeenCalledOnce();
    spy.mockRestore();
  });

  it("records `import.reprocess` for the existing reprocess route", async () => {
    const athlete = await t.seedUser("Athlète Import");
    const importId = randomUUID();
    await t.sql(
      `insert into activities.activity_import (id, user_id, format, original_file_name, size_bytes, status, error)
       values ($1, $2, 'gpx', 'run.gpx', 1000, 'failed', 'unreadable_file')`,
      [importId, athlete],
    );

    const response = await t.call(`/admin/activity-imports/${importId}/reprocess`, admin, {
      method: "POST",
      requestId: "req-import-1",
    });

    expect(response.status).toBe(202);
    const [entry] = await entriesBy(admin);
    expect(entry).toMatchObject({
      action: "import.reprocess",
      target_type: "activity_import",
      target_id: importId,
      reason: null,
      request_id: "req-import-1",
    });
  });
});
