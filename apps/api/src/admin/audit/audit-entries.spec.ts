import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { AuditActorListResponse, AuditEntryListResponse } from "@repo/contracts";
import { ActivitiesModule } from "@repo/core/activities";
import { EngagementModule } from "@repo/core/engagement";
import { containsIgnoringAccents, DATABASE, type Database } from "@repo/core/infrastructure";
import { ModerationModule } from "@repo/core/moderation";
import { schema } from "@repo/db";
import { bootstrapAdminTestApp, type AdminTestApp } from "../../testing/admin-test-app.js";
import { AuditEntriesController } from "./audit-entries.controller.js";
import { AuditEntryAssembler } from "./audit-entry-assembler.js";

/** `GET /v1/admin/audit-entries` and its author list: the Journal screen (ADR-038 §3). */
describe("GET /v1/admin/audit-entries (integration)", () => {
  let t: AdminTestApp;
  let admin: string;
  let otherAdmin: string;
  let athlete: string;
  /** An Administrator whose account was deleted since. */
  const goneAdmin = randomUUID();
  /** An athlete whose account was deleted since. */
  const goneAthlete = randomUUID();

  async function entry(values: {
    actorId: string | null;
    action: string;
    targetType: string;
    targetId: string | null;
    subjectUserId?: string | null;
    reason?: string | null;
    createdAt: string;
  }) {
    const id = randomUUID();
    await t.sql(
      `insert into audit.admin_audit_entry
         (id, actor_id, action, target_type, target_id, subject_user_id, reason, details, request_id, created_at)
       values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
      [
        id,
        values.actorId,
        values.action,
        values.targetType,
        values.targetId,
        values.subjectUserId ?? null,
        values.reason ?? null,
        null,
        "req-seeded",
        values.createdAt,
      ],
    );
    return id;
  }

  async function list(query: string) {
    const response = await t.call(`/admin/audit-entries?${query}`, admin);
    expect(response.status).toBe(200);
    return (await response.json()) as AuditEntryListResponse;
  }

  let banId: string;
  let roleId: string;
  let lateId: string;

  beforeAll(async () => {
    t = await bootstrapAdminTestApp({
      imports: [ActivitiesModule, EngagementModule, ModerationModule],
      controllers: [AuditEntriesController],
      providers: [AuditEntryAssembler],
    });
    admin = await t.seedUser("Alice Admin", { role: "admin" });
    otherAdmin = await t.seedUser("Bruno Admin", { role: "admin" });
    athlete = await t.seedUser("Émile Athlète");

    // 2026-11-01 23:30 in Paris is 22:30 UTC: a Paris "2026-11-01" entry.
    banId = await entry({
      actorId: admin,
      action: "user.ban",
      targetType: "user",
      targetId: athlete,
      subjectUserId: athlete,
      reason: "Spam",
      createdAt: "2026-11-01T22:30:00Z",
    });
    // 2026-11-02 00:30 in Paris (23:30 UTC on the 1st): a Paris "2026-11-02" entry.
    lateId = await entry({
      actorId: admin,
      action: "comment.remove",
      targetType: "comment",
      targetId: randomUUID(),
      subjectUserId: goneAthlete,
      reason: "Insulte",
      createdAt: "2026-11-01T23:30:00Z",
    });
    roleId = await entry({
      actorId: goneAdmin,
      action: "user.role.grant",
      targetType: "user",
      targetId: otherAdmin,
      subjectUserId: otherAdmin,
      createdAt: "2026-11-03T10:00:00Z",
    });
    await entry({
      actorId: null,
      action: "user.delete.complete",
      targetType: "user",
      targetId: goneAthlete,
      subjectUserId: goneAthlete,
      createdAt: "2026-11-03T11:00:00Z",
    });
  }, 30_000);

  afterAll(async () => {
    await t?.sql("delete from audit.admin_audit_entry where request_id = 'req-seeded'");
    await t?.close();
  });

  it("shows an entry with its author, target and athlete concerned", async () => {
    const page = await list(`actorId=${admin}&action=user.ban`);

    expect(page).toMatchObject({ total: 1, page: 1, pageSize: 50 });
    expect(page.items[0]).toEqual({
      id: banId,
      createdAt: "2026-11-01T22:30:00.000Z",
      action: "user.ban",
      actor: { id: admin, displayName: "Alice Admin" },
      target: { type: "user", id: athlete, exists: true },
      subject: { id: athlete, displayName: "Émile Athlète" },
      reason: "Spam",
      details: null,
      requestId: "req-seeded",
    });
  });

  it("names a deleted account with no name, and the system with no author", async () => {
    const page = await list(`subjectUserId=${goneAthlete}`);

    expect(page.items.map((item) => item.action)).toEqual(["user.delete.complete", "comment.remove"]);
    const [system, removal] = page.items;
    expect(system?.actor).toBeNull();
    expect(system?.subject).toEqual({ id: goneAthlete, displayName: null });
    expect(system?.target).toEqual({ type: "user", id: goneAthlete, exists: false });
    expect(removal?.id).toBe(lateId);

    const [promotion] = (await list(`subjectUserId=${otherAdmin}`)).items;
    expect(promotion).toMatchObject({ id: roleId, actor: { id: goneAdmin, displayName: null } });
  });

  it("cuts periods in Paris days, both ends included", async () => {
    const firstOfNovember = await list(`actorId=${admin}&from=2026-11-01&to=2026-11-01`);
    expect(firstOfNovember.items.map((item) => item.id)).toEqual([banId]);

    const fromTheSecond = await list(`actorId=${admin}&from=2026-11-02`);
    expect(fromTheSecond.items.map((item) => item.id)).toEqual([lateId]);
  });

  it("pages newest first with the total", async () => {
    const first = await list(`actorId=${admin}&pageSize=25&page=1`);
    expect(first.total).toBe(2);
    expect(first.items.map((item) => item.id)).toEqual([lateId, banId]);

    const beyond = await list(`actorId=${admin}&pageSize=25&page=2`);
    expect(beyond).toMatchObject({ items: [], total: 2, page: 2, pageSize: 25 });
  });

  it("refuses an unknown action, a page size outside 25/50/100 and a reversed period", async () => {
    for (const query of ["action=user.explode", "pageSize=10", "from=2026-11-03&to=2026-11-01"]) {
      expect((await t.call(`/admin/audit-entries?${query}`, admin)).status).toBe(422);
    }
  });

  it("lists every author of the Journal for the author filter, deleted ones included", async () => {
    const response = await t.call("/admin/audit-entries/actors", admin);
    expect(response.status).toBe(200);
    const { items } = (await response.json()) as AuditActorListResponse;

    expect(items).toEqual(
      expect.arrayContaining([
        { id: admin, displayName: "Alice Admin" },
        { id: goneAdmin, displayName: null },
      ]),
    );
  });

  it("is for Administrators only", async () => {
    expect((await t.call("/admin/audit-entries", athlete, { role: "user" })).status).toBe(403);
  });

  it("searches names ignoring case and accents (shared list helper)", async () => {
    const db = t.app.get<Database>(DATABASE);
    const matches = await db
      .select({ id: schema.user.id })
      .from(schema.user)
      .where(containsIgnoringAccents([schema.user.name, schema.user.email], "EMILE ath"));
    expect(matches.map((row) => row.id)).toEqual([athlete]);
  });
});
