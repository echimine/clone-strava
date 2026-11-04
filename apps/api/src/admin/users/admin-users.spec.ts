import { getQueueToken } from "@nestjs/bullmq";
import type { Queue } from "bullmq";
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi, type MockInstance } from "vitest";
import {
  EMAILS_QUEUE_NAME,
  sendEmailJobId,
  type SendEmailJob,
  type AdminUserDetail,
  type AdminUserListResponse,
  type AdminUserReportsResponse,
  type AdminUserSessionsResponse,
  type BannedUserError,
} from "@repo/contracts";
import type { AdminAuthTestApp, TestAccount } from "../../testing/admin-auth-test-app.js";
import { useExclusiveTestDatabase } from "../../testing/exclusive-test-database.js";
import type { SanctionNotice, SanctionNotices } from "../sanctions/sanction-notices.js";

type Entry = { action: string; actor_id: string; target_id: string; subject_user_id: string; reason: string | null; details: unknown };

/**
 * The backoffice users area (ADR-038 §5, §6, §17): list, sheet, sessions, Ban and the other user
 * Sanctions, roles. Real Better Auth (the admin plugin's `auth.api.*`), Postgres and Redis, on a
 * database of its own: the "last Administrator" rule and the list totals count every account.
 */
describe("/v1/admin/users (integration)", () => {
  let t: AdminAuthTestApp;
  let admin: TestAccount;
  let notices: MockInstance<SanctionNotices["send"]>;

  const json = async <T,>(response: Response, status = 200): Promise<T> => {
    expect(response.status, await response.clone().text()).toBe(status);
    return (await response.json()) as T;
  };
  const errorCode = async (response: Response) => ((await response.json()) as { error: { code: string } }).error.code;
  const post = (path: string, body: unknown = {}, as = admin.cookie) => t.call(path, as, { method: "POST", body });
  const entries = (subject: string) =>
    t.sql<Entry>("select * from audit.admin_audit_entry where subject_user_id = $1 order by created_at", [subject]);
  const lastNotice = (): SanctionNotice => notices.mock.calls.at(-1)![0];
  /** The `send-email` job of a Sanction (ADR-038 §4), keyed by its Journal entry. */
  const emailOf = async (auditEntryId: string) =>
    (await t.app.get<Queue>(getQueueToken(EMAILS_QUEUE_NAME)).getJob(sendEmailJobId(auditEntryId)))?.data as
      | SendEmailJob
      | undefined;
  /** The app's sign-in by Sign-in code: send the code (the dev code `000000`), then validate it. */
  const signInWithCode = async (email: string) => {
    expect((await t.authPost("/email-otp/send-verification-otp", { email, type: "sign-in" })).status).toBe(200);
    return t.authPost("/sign-in/email-otp", { email, otp: "000000" });
  };

  beforeAll(async () => {
    await useExclusiveTestDatabase("admin_users");
    const { bootstrapAdminAuthTestApp } = await import("../../testing/admin-auth-test-app.js");
    const { ActivitiesModule } = await import("@repo/core/activities");
    const { ModerationModule } = await import("@repo/core/moderation");
    const { EmailJobsModule } = await import("@repo/core/notifications");
    const { SocialModule } = await import("@repo/core/social");
    const { SubscriptionsModule } = await import("@repo/core/subscriptions");
    const { UsersModule } = await import("@repo/core/users");
    const { AthleteIdentities } = await import("../../identities/athlete-identities.js");
    const { SanctionNotices: Notices } = await import("../sanctions/sanction-notices.js");
    const { AdminUsersController } = await import("./admin-users.controller.js");
    const { AdminUserAssembler } = await import("./admin-user-assembler.js");
    t = await bootstrapAdminAuthTestApp({
      imports: [ActivitiesModule, EmailJobsModule, ModerationModule, SocialModule, SubscriptionsModule, UsersModule],
      controllers: [AdminUsersController],
      providers: [AthleteIdentities, AdminUserAssembler, Notices],
      contactEmail: "contact@nervo.test",
    });
    notices = vi.spyOn(t.app.get(Notices), "send");
    admin = await t.createAdmin("admin");
  }, 60_000);

  afterAll(async () => {
    await t?.close();
  });

  beforeEach(() => {
    notices.mockClear();
  });

  describe("Ban (ADR-038 §5, §6)", () => {
    it("bans for 7 days: sessions revoked, sign-in refused with 403 BANNED_USER, Journal and e-mail notice", async () => {
      const athlete = await t.createAthlete("bannie");
      const before = Date.now();
      expect((await post(`/admin/users/${athlete.userId}/ban`, { duration: "7d", reason: "Propos haineux" })).status).toBe(204);

      // The session is gone: the next request is a 401.
      expect((await t.call(`/admin/users/${athlete.userId}`, athlete.cookie)).status).toBe(401);

      // Sign-in by code: sending the code is accepted, validating it is refused.
      const signIn = await signInWithCode(athlete.email);
      expect(signIn.status).toBe(403);
      const body = (await signIn.json()) as BannedUserError;
      expect(body).toMatchObject({ code: "BANNED_USER", banReason: "Propos haineux", contactEmail: "contact@nervo.test" });
      const until = Date.parse(body.bannedUntil!);
      expect(until - before).toBeGreaterThanOrEqual(7 * 24 * 3600_000 - 1000);
      expect(until - before).toBeLessThan(7 * 24 * 3600_000 + 60_000);

      const [entry] = await entries(athlete.userId);
      expect(entry).toMatchObject({
        action: "user.ban",
        actor_id: admin.userId,
        target_id: athlete.userId,
        reason: "Propos haineux",
        details: { duration: "7d" },
      });
      expect(lastNotice()).toMatchObject({
        action: "user.ban",
        athleteId: athlete.userId,
        reason: "Propos haineux",
        ban: { until: body.bannedUntil },
      });
      expect(await emailOf(lastNotice().auditEntryId)).toEqual({
        template: "user-banned",
        to: athlete.email,
        idempotencyKey: lastNotice().auditEntryId,
        userId: athlete.userId,
        data: { firstName: "bannie", reason: "Propos haineux", until: body.bannedUntil },
      });
      expect((await entries(athlete.userId))[0]).toHaveProperty("id", lastNotice().auditEntryId);

      const detail = await json<AdminUserDetail>(await t.call(`/admin/users/${athlete.userId}`, admin.cookie));
      expect(detail.state).toBe("temporarily_banned");
      expect(detail.ban).toEqual({ until: body.bannedUntil, reason: "Propos haineux" });
    });

    it("banning again replaces the duration: permanent, « définitivement »", async () => {
      const athlete = await t.createAthlete("rebannie");
      await post(`/admin/users/${athlete.userId}/ban`, { duration: "24h", reason: "Spam" });
      expect((await post(`/admin/users/${athlete.userId}/ban`, { duration: "permanent", reason: "Récidive" })).status).toBe(204);

      const signIn = await signInWithCode(athlete.email);
      expect(await signIn.json()).toMatchObject({ code: "BANNED_USER", bannedUntil: null, banReason: "Récidive" });
      expect(lastNotice().ban).toEqual({ until: null });
      const detail = await json<AdminUserDetail>(await t.call(`/admin/users/${athlete.userId}`, admin.cookie));
      expect(detail.state).toBe("banned");
    });

    it("an expired Ban is over at once: sign-in works without an unban", async () => {
      const athlete = await t.createAthlete("expiree");
      await post(`/admin/users/${athlete.userId}/ban`, { duration: "24h", reason: "Spam" });
      await t.sql(`update "user" set ban_expires = now() - interval '1 minute' where id = $1`, [athlete.userId]);

      const detail = await json<AdminUserDetail>(await t.call(`/admin/users/${athlete.userId}`, admin.cookie));
      expect(detail).toMatchObject({ state: "active", ban: null });
      expect((await signInWithCode(athlete.email)).status).toBe(200);
    });

    it("refuses an Administrator (409 user_is_admin), a missing reason (400) and an unknown account (404)", async () => {
      const other = await t.createAdmin("other-admin");
      const refused = await post(`/admin/users/${other.userId}/ban`, { duration: "24h", reason: "Non" });
      expect(refused.status).toBe(409);
      expect(await errorCode(refused)).toBe("user_is_admin");

      const athlete = await t.createAthlete("sans-motif");
      const noReason = await post(`/admin/users/${athlete.userId}/ban`, { duration: "24h", reason: "  " });
      expect(noReason.status).toBe(400);
      expect(await errorCode(noReason)).toBe("reason_required");

      const unknown = await post(`/admin/users/${crypto.randomUUID()}/ban`, { duration: "24h", reason: "Spam" });
      expect(unknown.status).toBe(404);
      expect(await errorCode(unknown)).toBe("user_not_found");
      expect(notices).not.toHaveBeenCalled();
    });

    it("unban lifts it at once: sign-in works again, Journal and notice; 409 not_banned without a Ban", async () => {
      const athlete = await t.createAthlete("levee");
      await post(`/admin/users/${athlete.userId}/ban`, { duration: "30d", reason: "Spam" });
      expect((await post(`/admin/users/${athlete.userId}/unban`, { reason: "Erreur de ma part" })).status).toBe(204);

      expect((await signInWithCode(athlete.email)).status).toBe(200);
      expect((await entries(athlete.userId)).map((entry) => entry.action)).toEqual(["user.ban", "user.unban"]);
      expect(lastNotice()).toMatchObject({ action: "user.unban", reason: "Erreur de ma part" });

      const again = await post(`/admin/users/${athlete.userId}/unban`, { reason: "Encore" });
      expect(again.status).toBe(409);
      expect(await errorCode(again)).toBe("not_banned");
    });
  });

  it("« Déconnecter partout »: every session closes, the athlete can sign in again, no e-mail", async () => {
    const athlete = await t.createAthlete("deconnecte");
    const sessions = await json<AdminUserSessionsResponse>(
      await t.call(`/admin/users/${athlete.userId}/sessions`, admin.cookie),
    );
    expect(sessions.items).toHaveLength(1);
    expect(sessions.items[0]).toMatchObject({ device: "node", userAgent: "node" });
    expect(sessions.items[0]).not.toHaveProperty("token");

    expect((await post(`/admin/users/${athlete.userId}/sign-out`, { reason: "Compte compromis" })).status).toBe(204);
    expect((await t.call(`/admin/users/${athlete.userId}`, athlete.cookie)).status).toBe(401);
    expect(
      (await json<AdminUserSessionsResponse>(await t.call(`/admin/users/${athlete.userId}/sessions`, admin.cookie))).items,
    ).toEqual([]);
    expect((await signInWithCode(athlete.email)).status).toBe(200);
    expect((await entries(athlete.userId)).map((entry) => entry.action)).toEqual(["user.sign_out"]);
    expect(notices).not.toHaveBeenCalled();
  });

  describe("resets (ADR-038 §5)", () => {
    it("reset-name: first name « Athlète », empty last name, account name too", async () => {
      const athlete = await t.createAthlete("Insulte", { lastName: "Grossier" });
      expect((await post(`/admin/users/${athlete.userId}/reset-name`, { reason: "Nom injurieux" })).status).toBe(204);

      const [profile] = await t.sql<{ first_name: string; last_name: string }>(
        "select first_name, last_name from users.user_profile where user_id = $1",
        [athlete.userId],
      );
      expect(profile).toEqual({ first_name: "Athlète", last_name: "" });
      const [account] = await t.sql<{ name: string }>('select name from "user" where id = $1', [athlete.userId]);
      expect(account!.name).toBe("Athlète");
      expect(lastNotice()).toMatchObject({ action: "user.name.reset", profileField: "name", athleteId: athlete.userId });
      // The e-mail greets them by the first name they had chosen.
      expect(await emailOf(lastNotice().auditEntryId)).toMatchObject({
        template: "profile-reset",
        data: { firstName: "Insulte", reason: "Nom injurieux", field: "name" },
      });
      expect((await entries(athlete.userId))[0]).toMatchObject({ action: "user.name.reset", reason: "Nom injurieux" });
    });

    it("reset-bio empties the bio", async () => {
      const athlete = await t.createAthlete("bio", { bio: "Achetez mes produits" });
      expect((await post(`/admin/users/${athlete.userId}/reset-bio`, { reason: "Publicité" })).status).toBe(204);
      const [profile] = await t.sql<{ bio: string | null }>("select bio from users.user_profile where user_id = $1", [
        athlete.userId,
      ]);
      expect(profile!.bio).toBeNull();
      expect(lastNotice()).toMatchObject({ action: "user.bio.reset", profileField: "bio" });
    });

    it("reset-avatar removes the Avatar and deletes its object", async () => {
      const athlete = await t.createAthlete("avatar");
      const key = `avatars/${athlete.userId}/${crypto.randomUUID()}.jpg`;
      t.storage.objects.set(key, new Uint8Array([1, 2, 3]));
      await t.sql("update users.user_profile set avatar_key = $2 where user_id = $1", [athlete.userId, key]);

      expect((await post(`/admin/users/${athlete.userId}/reset-avatar`, { reason: "Image choquante" })).status).toBe(204);
      const [profile] = await t.sql<{ avatar_key: string | null }>(
        "select avatar_key from users.user_profile where user_id = $1",
        [athlete.userId],
      );
      expect(profile!.avatar_key).toBeNull();
      expect(t.storage.objects.has(key)).toBe(false);
      expect(lastNotice()).toMatchObject({ action: "user.avatar.reset", profileField: "avatar" });
    });
  });

  describe("role (ADR-038 §5)", () => {
    it("grants then removes the admin role, optional reason, user.role.grant / user.role.revoke", async () => {
      const athlete = await t.createAthlete("promue");
      expect((await t.call(`/admin/users/${athlete.userId}/role`, admin.cookie, { method: "PUT", body: { role: "admin" } })).status).toBe(204);
      expect((await json<AdminUserDetail>(await t.call(`/admin/users/${athlete.userId}`, admin.cookie))).role).toBe("admin");
      expect(
        (
          await t.call(`/admin/users/${athlete.userId}/role`, admin.cookie, {
            method: "PUT",
            body: { role: "user", reason: "Fin de mission" },
          })
        ).status,
      ).toBe(204);

      expect(await entries(athlete.userId)).toMatchObject([
        { action: "user.role.grant", reason: null },
        { action: "user.role.revoke", reason: "Fin de mission" },
      ]);
      expect(notices).not.toHaveBeenCalled();
    });

    it("refuses no change and a self-demotion (409)", async () => {
      const athlete = await t.createAthlete("inchangee");
      const unchanged = await t.call(`/admin/users/${athlete.userId}/role`, admin.cookie, { method: "PUT", body: { role: "user" } });
      expect(unchanged.status).toBe(409);
      expect(await errorCode(unchanged)).toBe("role_unchanged");

      const self = await t.call(`/admin/users/${admin.userId}/role`, admin.cookie, { method: "PUT", body: { role: "user" } });
      expect(self.status).toBe(409);
      expect(await errorCode(self)).toBe("cannot_demote_self");

      // No `409 last_admin` through the API: an actor is an Administrator, so demoting another one
      // always leaves one. The rule stays in `SetUserRoleUseCase` against races.
    });
  });

  describe("list and sheet (ADR-038 §5)", () => {
    it("searches first name, last name and e-mail ignoring accents; filters role, state, method, Premium; sorts", async () => {
      const tag = `zq${crypto.randomUUID().slice(0, 6)}`;
      const emilie = await t.createAthlete("emilie", { firstName: "Émilie", lastName: tag });
      const bruno = await t.createAthlete("bruno", { firstName: "Bruno", lastName: tag });
      await t.sql(
        `insert into activities.activity (id, user_id, sport_type_code, title, started_at, ended_at, visibility, processing_status)
         values (gen_random_uuid(), $1, 'run', 'Sortie', '2026-10-01T08:00:00Z', '2026-10-01T09:00:00Z', 'private', 'processed'),
                (gen_random_uuid(), $1, 'run', 'Sortie', '2026-10-03T08:00:00Z', '2026-10-03T09:00:00Z', 'public', 'failed')`,
        [bruno.userId],
      );
      await t.sql(
        `insert into subscriptions.user_subscription (user_id, is_active, store, expires_at, will_renew)
         values ($1, true, 'app_store', now() + interval '10 days', true)`,
        [emilie.userId],
      );
      await t.sql(`insert into account (user_id, account_id, provider_id) values ($1, 'g-1', 'google')`, [bruno.userId]);
      await post(`/admin/users/${emilie.userId}/ban`, { duration: "24h", reason: "Spam" });

      const search = await json<AdminUserListResponse>(await t.call(`/admin/users?q=emilie%20${tag}`, admin.cookie));
      expect(search.items.map((item) => item.athlete.id)).toEqual([emilie.userId]);
      expect(search.items[0]).toMatchObject({
        athlete: { displayName: `Émilie ${tag}`, avatarUrl: null },
        email: emilie.email,
        role: "user",
        signInMethods: ["email_code", "password"],
        activityCount: 0,
        lastActivityAt: null,
        isPremium: true,
        state: "temporarily_banned",
        ban: { reason: "Spam" },
      });

      const byLastActivity = await json<AdminUserListResponse>(
        await t.call(`/admin/users?q=${tag}&sort=lastActivityAt&order=desc`, admin.cookie),
      );
      expect(byLastActivity.items.map((item) => item.athlete.id)).toEqual([bruno.userId, emilie.userId]);
      expect(byLastActivity.items[0]).toMatchObject({
        activityCount: 2,
        lastActivityAt: "2026-10-03T08:00:00.000Z",
        signInMethods: ["google", "password"],
        isPremium: false,
        state: "active",
      });

      const ids = async (query: string) =>
        (await json<AdminUserListResponse>(await t.call(`/admin/users?q=${tag}&${query}`, admin.cookie))).items.map(
          (item) => item.athlete.id,
        );
      expect(await ids("state=temporarily_banned")).toEqual([emilie.userId]);
      expect(await ids("state=active")).toEqual([bruno.userId]);
      expect(await ids("state=banned")).toEqual([]);
      expect(await ids("method=google")).toEqual([bruno.userId]);
      expect(await ids("method=email_code")).toEqual([emilie.userId]);
      expect(await ids("premium=yes")).toEqual([emilie.userId]);
      expect(await ids("premium=no")).toEqual([bruno.userId]);
      expect(await ids("role=admin")).toEqual([]);

      const admins = await json<AdminUserListResponse>(await t.call(`/admin/users?role=admin`, admin.cookie));
      expect(admins.items.every((item) => item.role === "admin")).toBe(true);
      expect(admins.total).toBeGreaterThanOrEqual(1);
    });

    it("the sheet: account, athlete profile without birth date, gender or weight, Activity, Follows and « Bloqué par N »", async () => {
      const athlete = await t.createAthlete("fiche", { firstName: "Fiona", lastName: "Fiche", bio: "Trail" });
      const fan = await t.createAthlete("fan");
      const blocker = await t.createAthlete("bloqueur");
      await t.sql(
        `update users.user_profile set city = 'Annecy', country = 'FR', level = 'advanced', default_visibility = 'followers',
           birth_date = '1990-01-01', gender = 'female', weight_kg = 60 where user_id = $1`,
        [athlete.userId],
      );
      await t.sql(`insert into users.user_sport (user_id, sport_code, position) values ($1, 'run', 0)`, [athlete.userId]);
      await t.sql(`insert into social.follow (follower_id, followee_id, status) values ($1, $2, 'accepted')`, [
        fan.userId,
        athlete.userId,
      ]);
      await t.sql(`insert into social.athlete_block (blocker_id, blocked_id) values ($1, $2)`, [blocker.userId, athlete.userId]);

      const detail = await json<AdminUserDetail>(await t.call(`/admin/users/${athlete.userId}`, admin.cookie));
      expect(detail).toMatchObject({
        athlete: { id: athlete.userId, displayName: "Fiona Fiche", avatarUrl: null },
        email: athlete.email,
        role: "user",
        state: "active",
        ban: null,
        premium: { active: false, billedByAppStore: false },
        account: { signInMethods: ["email_code", "password"], twoFactorEnabled: false },
        profile: {
          firstName: "Fiona",
          lastName: "Fiche",
          bio: "Trail",
          city: "Annecy",
          country: "FR",
          sports: ["run"],
          level: "advanced",
          defaultVisibility: "followers",
        },
        activity: { activityCount: 0, lastActivityAt: null, streakWeeks: 0 },
        follows: { followerCount: 1, followingCount: 0, blockedByCount: 1 },
      });
      const serialized = JSON.stringify(detail);
      expect(serialized).not.toContain("1990-01-01");
      expect(serialized).not.toContain("female");
      expect(serialized).not.toMatch(/weight/i);

      const unknown = await t.call(`/admin/users/${crypto.randomUUID()}`, admin.cookie);
      expect(unknown.status).toBe(404);
    });

    it("the « Signalements » tabs: Reports received and sent, with their case", async () => {
      const athlete = await t.createAthlete("signalee");
      const reporter = await t.createAthlete("signaleur");
      const [reportCase] = await t.sql<{ id: string }>(
        `insert into moderation.report_case (target_type, target_id, target_user_id) values ('athlete', $1, $1) returning id`,
        [athlete.userId],
      );
      await t.sql(`insert into moderation.report (case_id, reporter_id, reason) values ($1, $2, 'spam')`, [
        reportCase!.id,
        reporter.userId,
      ]);

      const received = await json<AdminUserReportsResponse>(await t.call(`/admin/users/${athlete.userId}/reports`, admin.cookie));
      expect(received.sent).toEqual([]);
      expect(received.received).toMatchObject([
        { caseId: reportCase!.id, targetType: "athlete", reason: "spam", status: "open" },
      ]);
      const sent = await json<AdminUserReportsResponse>(await t.call(`/admin/users/${reporter.userId}/reports`, admin.cookie));
      expect(sent.sent).toMatchObject([{ caseId: reportCase!.id, reason: "spam" }]);
      expect(sent.received).toEqual([]);
    });
  });
});
