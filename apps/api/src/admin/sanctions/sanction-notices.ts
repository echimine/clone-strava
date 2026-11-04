import { Injectable, Logger } from "@nestjs/common";
import type { AuditAction, RemovedContent, SendEmailJob } from "@repo/contracts";
import { AuthService } from "@repo/core/auth";
import { EmailJobs } from "@repo/core/notifications";
import { UsersService } from "@repo/core/users";

/** Who the e-mail goes to: read before the Sanction when it changes them (a name reset). */
export interface SanctionRecipient {
  email: string;
  /** The profile's first name; null greets without a name. */
  firstName: string | null;
}

/**
 * What the e-mail to the athlete after a Sanction must name (ADR-038 §4), gathered by the
 * Sanction's handler right after it succeeds, while the content still exists: "votre Activité
 * « Sortie du dimanche » du 2 novembre", a removed comment quoted. Never a link, never the
 * Report. The recipient's address and first name are read from `athleteId` when the job is
 * enqueued (the account may be gone by the time it runs), unless `recipient` already holds them.
 */
export interface SanctionNotice {
  /** The Journal entry of the Sanction: the e-mail's idempotency key. */
  auditEntryId: string;
  action: Extract<
    AuditAction,
    | "activity.delete"
    | "media.remove"
    | "activity.text.reset"
    | "comment.remove"
    | "user.ban"
    | "user.unban"
    | "user.name.reset"
    | "user.bio.reset"
    | "user.avatar.reset"
  >;
  /** The athlete sanctioned: the author of the content, or the account itself. */
  athleteId: string;
  /** As the Administrator typed it; the athlete reads it. */
  reason: string;
  /** The Activity concerned, as the athlete knew it (before a reset); null if already gone. */
  activity: { title: string; startedAt: string } | null;
  /** The removed comment's text and when it was posted, for `comment.remove` only. */
  comment: { body: string; postedAt?: string | null } | null;
  /**
   * For `user.ban`: the Ban's end, null for a permanent one (« définitivement »); for
   * `user.unban`: the Ban lifted. Absent for content Sanctions.
   */
  ban?: { until: string | null } | null;
  /** For the `user.*.reset` Sanctions: which profile field went back to its default. */
  profileField?: "name" | "bio" | "avatar" | null;
  /** Read with {@link SanctionNotices.recipientOf} before a Sanction that changes the first name. */
  recipient?: SanctionRecipient;
}

type SanctionEmail = Pick<SendEmailJob, "template" | "data">;

/**
 * The single hook point between the backoffice Sanctions and the e-mails to the athlete
 * (ADR-038 §4). Every Sanction handler calls {@link send} once it has succeeded, except
 * « Déconnecter partout », which sends no e-mail: one `send-email` job of the `emails` queue,
 * with the Journal entry id as idempotency key.
 */
@Injectable()
export class SanctionNotices {
  private readonly logger = new Logger(SanctionNotices.name);

  constructor(
    private readonly auth: AuthService,
    private readonly users: UsersService,
    private readonly emails: EmailJobs,
  ) {}

  /** The athlete's address and first name, as they are now. */
  async recipientOf(athleteId: string): Promise<SanctionRecipient> {
    const [account, profile] = await Promise.all([
      this.auth.getAccountForAdmin(athleteId),
      this.users.getAdminProfile(athleteId),
    ]);
    return { email: account.email, firstName: profile.firstName?.trim() || null };
  }

  /**
   * Enqueues the e-mail of a Sanction that succeeded. Never throws: the Sanction is done and its
   * Journal entry still to be written, so a failure here is only logged.
   */
  async send(notice: SanctionNotice): Promise<void> {
    try {
      const recipient = notice.recipient ?? (await this.recipientOf(notice.athleteId));
      const email = sanctionEmail(notice, recipient.firstName);
      await this.emails.enqueue({
        ...email,
        to: recipient.email,
        idempotencyKey: notice.auditEntryId,
        userId: notice.athleteId,
      } as SendEmailJob);
    } catch (error) {
      this.logger.error(
        `Sanction ${notice.action} (${notice.auditEntryId}): e-mail to athlete ${notice.athleteId} not enqueued: ${String(error)}`,
      );
    }
  }
}

/** The template and data of a Sanction's e-mail. */
function sanctionEmail(notice: SanctionNotice, firstName: string | null): SanctionEmail {
  const { reason } = notice;
  switch (notice.action) {
    case "user.ban":
      return { template: "user-banned", data: { firstName, reason, until: notice.ban?.until ?? null } };
    case "user.unban":
      return { template: "user-unbanned", data: { firstName, reason } };
    case "user.name.reset":
    case "user.bio.reset":
    case "user.avatar.reset":
      return { template: "profile-reset", data: { firstName, reason, field: profileField(notice) } };
    case "activity.delete":
    case "media.remove":
    case "activity.text.reset":
    case "comment.remove":
      return { template: "content-removed", data: { firstName, reason, content: removedContent(notice) } };
  }
}

function profileField(notice: SanctionNotice): "name" | "bio" | "avatar" {
  return notice.profileField ?? (notice.action.split(".")[1] as "name" | "bio" | "avatar");
}

function removedContent(notice: SanctionNotice): RemovedContent {
  if (notice.action === "comment.remove") {
    return {
      kind: "comment",
      body: notice.comment?.body ?? "",
      postedAt: notice.comment?.postedAt ?? null,
      activity: notice.activity,
    };
  }
  if (!notice.activity) {
    throw new Error(`${notice.action} needs the Activity it names`);
  }
  const kind = ({ "activity.delete": "activity", "media.remove": "media", "activity.text.reset": "activity-text" } as const)[
    notice.action as "activity.delete" | "media.remove" | "activity.text.reset"
  ];
  return { kind, activity: notice.activity };
}
