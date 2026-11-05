import { randomUUID } from "node:crypto";
import { getQueueToken } from "@nestjs/bullmq";
import { EventEmitter2 } from "@nestjs/event-emitter";
import type { Queue } from "bullmq";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  ACCOUNT_DELETED_EVENT,
  ACCOUNTS_QUEUE_NAME,
  EMAILS_QUEUE_NAME,
  deleteAccountJobId,
  sendEmailJobId,
  type AccountDeletedEvent,
  type DeleteAccountJob,
  type SendEmailJob,
} from "@repo/contracts";
import type { AdminAuthTestApp, TestAccount } from "../testing/admin-auth-test-app.js";
import { useExclusiveTestDatabase } from "../testing/exclusive-test-database.js";

type Entry = {
  id: string;
  action: string;
  actor_id: string | null;
  target_id: string;
  subject_user_id: string;
  reason: string | null;
  details: unknown;
};

/**
 * Account deletion (ADR-038 §13), from the app (`/v1/me/account-deletion*`, re-verified by a
 * Sign-in code) and from the backoffice (`DELETE /v1/admin/users/:id`, a Sanction). Real Better
 * Auth, Postgres and Redis; the dev Sign-in code `000000` of `@stravaclone.test` addresses.
 */
describe("account deletion (integration)", () => {
  let t: AdminAuthTestApp;
  let admin: TestAccount;
  const deleted: AccountDeletedEvent[] = [];

  const errorCode = async (response: Response) => ((await response.json()) as { error: { code: string } }).error.code;
  const entries = (subject: string) =>
    t.sql<Entry>("select * from audit.admin_audit_entry where subject_user_id = $1 order by created_at", [subject]);
  const userExists = async (id: string) => (await t.sql('select 1 from "user" where id = $1', [id])).length === 1;
  const emailOf = async (key: string) =>
    (await t.app.get<Queue>(getQueueToken(EMAILS_QUEUE_NAME)).getJob(sendEmailJobId(key)))?.data as SendEmailJob | undefined;
  const cleanupOf = async (userId: string) =>
    (await t.app.get<Queue>(getQueueToken(ACCOUNTS_QUEUE_NAME)).getJob(deleteAccountJobId(userId))) ?? undefined;
  const requestCode = (account: TestAccount) => t.call("/me/account-deletion/code", account.cookie, { method: "POST", body: {} });
  const confirm = (account: TestAccount, code: string) =>
    t.call("/me/account-deletion", account.cookie, { method: "POST", body: { code } });

  /** A Report `reporter` sent about `target`, with a note. */
  async function seedReport(reporterId: string, targetUserId: string): Promise<string> {
    const [reportCase] = await t.sql<{ id: string }>(
      "insert into moderation.report_case (target_type, target_id, target_user_id) values ('athlete', $1, $1) returning id",
      [targetUserId],
    );
    const [report] = await t.sql<{ id: string }>(
      "insert into moderation.report (case_id, reporter_id, reason, note) values ($1, $2, 'other', 'Il m''a écrit à Lyon') returning id",
      [reportCase!.id, reporterId],
    );
    return report!.id;
  }

  /** A Segment drawn by `creatorId`, with an Effort of each athlete of `effortsBy`. */
  async function seedSegment(creatorId: string, effortsBy: string[]): Promise<string> {
    const [segment] = await t.sql<{ id: string }>(
      "insert into segments.segment (name, sport_type_code, created_by) values ('Montée', 'run', $1) returning id",
      [creatorId],
    );
    for (const userId of effortsBy) {
      const [activity] = await t.sql<{ id: string }>(
        `insert into activities.activity (id, user_id, sport_type_code, title, started_at, ended_at, visibility, processing_status)
         values ($1, $2, 'run', 'Sortie', now(), now() + interval '1 hour', 'public', 'processed') returning id`,
        [randomUUID(), userId],
      );
      await t.sql(
        `insert into segments.segment_effort (activity_id, segment_id, user_id, elapsed_time_s, started_at, start_index,
           end_index, min_distance_to_activity_start_m, min_distance_to_activity_end_m)
         values ($1, $2, $3, 300, now(), 0, 10, 1000, 1000)`,
        [activity!.id, segment!.id, userId],
      );
    }
    return segment!.id;
  }
  const segmentCreator = async (id: string) =>
    (await t.sql<{ created_by: string | null }>("select created_by from segments.segment where id = $1", [id]))[0];

  beforeAll(async () => {
    await useExclusiveTestDatabase("account_deletion");
    const { bootstrapAdminAuthTestApp } = await import("../testing/admin-auth-test-app.js");
    const { ActivitiesModule } = await import("@repo/core/activities");
    const { ModerationModule } = await import("@repo/core/moderation");
    const { EmailJobsModule } = await import("@repo/core/notifications");
    const { SocialModule } = await import("@repo/core/social");
    const { SegmentsModule } = await import("@repo/core/segments");
    const { SubscriptionsModule } = await import("@repo/core/subscriptions");
    const { AccountJobsModule, UsersModule } = await import("@repo/core/users");
    const { AthleteIdentities } = await import("../identities/athlete-identities.js");
    const { SanctionNotices } = await import("../admin/sanctions/sanction-notices.js");
    const { AdminUsersController } = await import("../admin/users/admin-users.controller.js");
    const { AdminUserAssembler } = await import("../admin/users/admin-user-assembler.js");
    const { MeAccountDeletionController } = await import("../me/me-account-deletion.controller.js");
    const { AccountDeletion } = await import("./account-deletion.js");
    t = await bootstrapAdminAuthTestApp({
      imports: [
        AccountJobsModule,
        ActivitiesModule,
        EmailJobsModule,
        ModerationModule,
        SegmentsModule,
        SocialModule,
        SubscriptionsModule,
        UsersModule,
      ],
      controllers: [AdminUsersController, MeAccountDeletionController],
      providers: [AthleteIdentities, AdminUserAssembler, SanctionNotices, AccountDeletion],
      contactEmail: "contact@nervo.test",
    });
    t.app.get(EventEmitter2).on(ACCOUNT_DELETED_EVENT, (event: AccountDeletedEvent) => deleted.push(event));
    admin = await t.createAdmin("admin");
  }, 60_000);

  afterAll(async () => {
    await t?.close();
  });

  beforeEach(() => {
    deleted.length = 0;
  });

  describe("from the app (POST /v1/me/account-deletion)", () => {
    it("re-verified by a Sign-in code: the account and its sessions are gone, its Reports stay without note", async () => {
      const athlete = await t.createAthlete("partante", { firstName: "Léa" });
      const other = await t.createAthlete("autre");
      const reportId = await seedReport(athlete.userId, other.userId);

      expect((await requestCode(athlete)).status).toBe(204);
      const response = await confirm(athlete, "000000");
      expect(response.status, await response.clone().text()).toBe(204);

      expect(await userExists(athlete.userId)).toBe(false);
      expect((await t.call("/me/account-deletion/code", athlete.cookie, { method: "POST", body: {} })).status).toBe(401);
      expect(await t.sql("select reporter_id, note from moderation.report where id = $1", [reportId])).toEqual([
        { reporter_id: null, note: null },
      ]);

      // « Compte supprimé », without author, no e-mail nor name kept.
      const [entry] = await entries(athlete.userId);
      expect(entry).toMatchObject({
        action: "user.delete",
        actor_id: null,
        target_id: athlete.userId,
        reason: null,
        details: { origin: "athlete" },
      });
      expect(JSON.stringify(entry)).not.toContain(athlete.email);

      expect(await emailOf(entry!.id)).toEqual({
        template: "account-deleted",
        to: athlete.email,
        idempotencyKey: entry!.id,
        userId: athlete.userId,
        data: { firstName: "Léa", reason: null },
      });
      const cleanup = await cleanupOf(athlete.userId);
      expect(cleanup?.name).toBe("delete-account");
      expect((cleanup?.data as DeleteAccountJob).userId).toBe(athlete.userId);
      expect(cleanup?.opts.attempts).toBe(5);
      expect(deleted).toEqual([{ userId: athlete.userId, bySanction: false }]);
    });

    it("the confirmation screen learns whether Apple keeps billing a Premium subscription", async () => {
      const free = await t.createAthlete("gratuite");
      const paying = await t.createAthlete("abonnee");
      await t.sql(
        `insert into subscriptions.user_subscription (user_id, is_active, store, period_type, will_renew, expires_at)
         values ($1, true, 'app_store', 'normal', true, now() + interval '20 days')`,
        [paying.userId],
      );
      const preview = async (account: TestAccount) => (await t.call("/me/account-deletion", account.cookie)).json();
      expect(await preview(free)).toEqual({ appStoreBilled: false });
      expect(await preview(paying)).toEqual({ appStoreBilled: true });
    });

    it("deletes the athlete's Segments nobody else has an Effort on; the others stay without creator", async () => {
      const athlete = await t.createAthlete("createur");
      const other = await t.createAthlete("passant");
      const onlyTheirs = await seedSegment(athlete.userId, [athlete.userId]);
      const untouched = await seedSegment(athlete.userId, []);
      const shared = await seedSegment(athlete.userId, [athlete.userId, other.userId]);
      const notTheirs = await seedSegment(other.userId, [athlete.userId]);

      expect((await requestCode(athlete)).status).toBe(204);
      expect((await confirm(athlete, "000000")).status).toBe(204);

      expect(await segmentCreator(onlyTheirs)).toBeUndefined();
      expect(await segmentCreator(untouched)).toBeUndefined();
      expect(await segmentCreator(shared)).toEqual({ created_by: null });
      expect(await segmentCreator(notTheirs)).toEqual({ created_by: other.userId });
      // The athlete's own Efforts go by cascade; the others' stay.
      expect(await t.sql("select user_id from segments.segment_effort where segment_id = $1", [shared])).toEqual([
        { user_id: other.userId },
      ]);
    });

    it("a wrong code is a 400 and deletes nothing", async () => {
      const athlete = await t.createAthlete("hesitante");
      await requestCode(athlete);
      const response = await confirm(athlete, "123456");
      expect(response.status).toBe(400);
      expect(await errorCode(response)).toBe("invalid_code");
      expect(await userExists(athlete.userId)).toBe(true);
      expect(await cleanupOf(athlete.userId)).toBeUndefined();
      expect(deleted).toEqual([]);
    });

    it("without a code sent first, the code is refused", async () => {
      const athlete = await t.createAthlete("pressee");
      const response = await confirm(athlete, "000000");
      expect(response.status).toBe(400);
      expect(await userExists(athlete.userId)).toBe(true);
    });

    it("an Administrator cannot delete their account (403), not even ask for the code", async () => {
      const otherAdmin = await t.createAdmin("admin-partant");
      for (const response of [await requestCode(otherAdmin), await confirm(otherAdmin, "000000")]) {
        expect(response.status).toBe(403);
        expect(await errorCode(response)).toBe("admin_cannot_delete_account");
      }
      expect(await userExists(otherAdmin.userId)).toBe(true);
    });
  });

  describe("from the backoffice (DELETE /v1/admin/users/:id)", () => {
    const remove = (id: string, body: unknown) => t.call(`/admin/users/${id}`, admin.cookie, { method: "DELETE", body });

    it("a Sanction: account gone, Journal with the reason, e-mail with the reason, cleanup job, event", async () => {
      const athlete = await t.createAthlete("sanctionnee", { firstName: "Zoé" });
      const reportId = await seedReport(athlete.userId, randomUUID());

      expect((await remove(athlete.userId, { reason: "Demande de l'athlète" })).status).toBe(204);

      expect(await userExists(athlete.userId)).toBe(false);
      expect((await t.call(`/admin/users/${athlete.userId}`, athlete.cookie)).status).toBe(401);
      expect(await t.sql("select reporter_id, note from moderation.report where id = $1", [reportId])).toEqual([
        { reporter_id: null, note: null },
      ]);
      const [entry] = await entries(athlete.userId);
      expect(entry).toMatchObject({
        action: "user.delete",
        actor_id: admin.userId,
        target_id: athlete.userId,
        reason: "Demande de l'athlète",
        details: { origin: "admin" },
      });
      expect(await emailOf(entry!.id)).toEqual({
        template: "account-deleted",
        to: athlete.email,
        idempotencyKey: entry!.id,
        userId: athlete.userId,
        data: { firstName: "Zoé", reason: "Demande de l'athlète" },
      });
      expect((await cleanupOf(athlete.userId))?.data).toMatchObject({ userId: athlete.userId });
      expect(deleted).toEqual([{ userId: athlete.userId, bySanction: true }]);
      expect((await t.call(`/admin/users/${athlete.userId}`, admin.cookie)).status).toBe(404);
    });

    it("a Sanction deletes the Segments only the athlete has Efforts on, keeps the others", async () => {
      const athlete = await t.createAthlete("createur-sanctionne");
      const other = await t.createAthlete("passant-sanction");
      const onlyTheirs = await seedSegment(athlete.userId, [athlete.userId]);
      const shared = await seedSegment(athlete.userId, [other.userId]);

      expect((await remove(athlete.userId, { reason: "Spam de Segments" })).status).toBe(204);
      expect(await segmentCreator(onlyTheirs)).toBeUndefined();
      expect(await segmentCreator(shared)).toEqual({ created_by: null });
    });

    it("refuses an Administrator (409 user_is_admin, notes kept), a missing reason (400) and an unknown account (404)", async () => {
      const otherAdmin = await t.createAdmin("admin-cible");
      const reportId = await seedReport(otherAdmin.userId, randomUUID());
      const adminSegment = await seedSegment(otherAdmin.userId, []);
      const conflict = await remove(otherAdmin.userId, { reason: "Test" });
      expect(conflict.status).toBe(409);
      expect(await errorCode(conflict)).toBe("user_is_admin");
      expect(await t.sql("select note from moderation.report where id = $1", [reportId])).toEqual([
        { note: "Il m'a écrit à Lyon" },
      ]);
      expect(await segmentCreator(adminSegment)).toEqual({ created_by: otherAdmin.userId });

      const athlete = await t.createAthlete("sans-motif");
      const noReason = await remove(athlete.userId, {});
      expect(noReason.status).toBe(400);
      expect(await errorCode(noReason)).toBe("reason_required");
      expect(await userExists(athlete.userId)).toBe(true);

      expect((await remove(randomUUID(), { reason: "Test" })).status).toBe(404);
      expect(deleted).toEqual([]);
    });
  });
});
