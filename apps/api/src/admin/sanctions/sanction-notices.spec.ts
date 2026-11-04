import { randomUUID } from "node:crypto";
import { getQueueToken } from "@nestjs/bullmq";
import type { Queue } from "bullmq";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { EMAILS_QUEUE_NAME, sendEmailJobId, type SendEmailJob } from "@repo/contracts";
import { EmailJobsModule } from "@repo/core/notifications";
import { UsersModule } from "@repo/core/users";
import { bootstrapAdminAuthTestApp, type AdminAuthTestApp, type TestAccount } from "../../testing/admin-auth-test-app.js";
import { SanctionNotices, type SanctionNotice } from "./sanction-notices.js";

const sortie = { title: "Sortie du dimanche", startedAt: "2026-11-02T08:30:00.000Z" };

/**
 * A Sanction's notice becomes one `send-email` job (ADR-038 §4): the athlete's address and first
 * name read at once, what the e-mail names copied in, the Journal entry id as idempotency key.
 * Real Better Auth and Postgres; the queue on real Redis, no worker.
 */
describe("SanctionNotices", () => {
  let t: AdminAuthTestApp;
  let athlete: TestAccount;

  const notices = () => t.app.get(SanctionNotices);
  const queue = () => t.app.get<Queue>(getQueueToken(EMAILS_QUEUE_NAME));
  const jobOf = async (auditEntryId: string): Promise<SendEmailJob | undefined> =>
    (await queue().getJob(sendEmailJobId(auditEntryId)))?.data as SendEmailJob | undefined;

  function notice(overrides: Partial<SanctionNotice> & Pick<SanctionNotice, "action">): SanctionNotice {
    return {
      auditEntryId: randomUUID(),
      athleteId: athlete.userId,
      reason: "Propos injurieux",
      activity: null,
      comment: null,
      ...overrides,
    };
  }

  beforeAll(async () => {
    t = await bootstrapAdminAuthTestApp({
      imports: [UsersModule, EmailJobsModule],
      controllers: [],
      providers: [SanctionNotices],
    });
    athlete = await t.createAthlete("lea", { firstName: "Léa" });
  }, 60_000);

  afterAll(async () => {
    await t?.close();
  });

  it("a Ban: the Ban e-mail to the athlete, its end, under the Journal entry id", async () => {
    const sent = notice({ action: "user.ban", ban: { until: "2026-11-11T13:30:00.000Z" } });

    await notices().send(sent);

    expect(await jobOf(sent.auditEntryId)).toEqual({
      template: "user-banned",
      to: athlete.email,
      idempotencyKey: sent.auditEntryId,
      userId: athlete.userId,
      data: { firstName: "Léa", reason: "Propos injurieux", until: "2026-11-11T13:30:00.000Z" },
    });
  });

  it("a permanent Ban, and its lifting", async () => {
    const ban = notice({ action: "user.ban", ban: { until: null } });
    const unban = notice({ action: "user.unban", reason: "Erreur", ban: { until: null } });

    await notices().send(ban);
    await notices().send(unban);

    expect(await jobOf(ban.auditEntryId)).toMatchObject({ template: "user-banned", data: { until: null } });
    expect(await jobOf(unban.auditEntryId)).toMatchObject({
      template: "user-unbanned",
      data: { firstName: "Léa", reason: "Erreur" },
    });
  });

  it.each([
    ["activity.delete", "activity"],
    ["media.remove", "media"],
    ["activity.text.reset", "activity-text"],
  ] as const)("%s: « Contenu retiré » naming the Activity", async (action, kind) => {
    const sent = notice({ action, activity: sortie });

    await notices().send(sent);

    expect(await jobOf(sent.auditEntryId)).toMatchObject({
      template: "content-removed",
      data: { firstName: "Léa", reason: "Propos injurieux", content: { kind, activity: sortie } },
    });
  });

  it("a comment removed: quoted, with its day and Activity", async () => {
    const sent = notice({
      action: "comment.remove",
      activity: sortie,
      comment: { body: "Quelle allure de tortue", postedAt: "2026-11-03T21:00:00.000Z" },
    });

    await notices().send(sent);

    expect(await jobOf(sent.auditEntryId)).toMatchObject({
      template: "content-removed",
      data: {
        content: { kind: "comment", body: "Quelle allure de tortue", postedAt: "2026-11-03T21:00:00.000Z", activity: sortie },
      },
    });
  });

  it("a profile reset names the field", async () => {
    const sent = notice({ action: "user.avatar.reset", profileField: "avatar" });

    await notices().send(sent);

    expect(await jobOf(sent.auditEntryId)).toMatchObject({ template: "profile-reset", data: { field: "avatar" } });
  });

  it("a name reset greets with the first name read before the reset", async () => {
    const recipient = await notices().recipientOf(athlete.userId);
    await t.sql("update users.user_profile set first_name = 'Athlète' where user_id = $1", [athlete.userId]);
    const sent = notice({ action: "user.name.reset", profileField: "name", recipient });

    await notices().send(sent);
    await t.sql("update users.user_profile set first_name = 'Léa' where user_id = $1", [athlete.userId]);

    expect(await jobOf(sent.auditEntryId)).toMatchObject({ template: "profile-reset", data: { firstName: "Léa", field: "name" } });
  });

  it("never fails the Sanction: an unknown athlete enqueues nothing and does not throw", async () => {
    const sent = notice({ action: "user.bio.reset", profileField: "bio", athleteId: randomUUID() });

    await expect(notices().send(sent)).resolves.toBeUndefined();
    expect(await jobOf(sent.auditEntryId)).toBeUndefined();
  });
});
