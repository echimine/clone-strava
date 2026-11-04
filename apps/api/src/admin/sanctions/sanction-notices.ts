import { Injectable, Logger } from "@nestjs/common";
import type { AuditAction } from "@repo/contracts";

/**
 * What the e-mail to the athlete after a Sanction must name (ADR-038 §4), gathered by the
 * Sanction's handler right after it succeeds, while the content still exists: "votre Activité
 * « Sortie du dimanche » du 2 novembre", a removed comment quoted. Never a link, never the
 * Report. The recipient's address and first name are read from `athleteId` when the job is
 * enqueued (the account may be gone by the time it runs).
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
  /** The removed comment's text, for `comment.remove` only. */
  comment: { body: string } | null;
  /**
   * For `user.ban`: the Ban's end, null for a permanent one (« définitivement »); for
   * `user.unban`: the Ban lifted. Absent for content Sanctions.
   */
  ban?: { until: string | null } | null;
  /** For the `user.*.reset` Sanctions: which profile field went back to its default. */
  profileField?: "name" | "bio" | "avatar" | null;
}

/**
 * The single hook point between the backoffice Sanctions and the e-mails to the athlete
 * (ADR-038 §4). Every Sanction handler calls {@link send} once it has succeeded, except
 * « Déconnecter partout », which sends no e-mail.
 *
 * TODO(#218): enqueue the `send-email` job of the `emails` queue here, with
 * `notice.auditEntryId` as idempotency key; until then nothing is sent.
 */
@Injectable()
export class SanctionNotices {
  private readonly logger = new Logger(SanctionNotices.name);

  async send(notice: SanctionNotice): Promise<void> {
    this.logger.debug(`Sanction ${notice.action} (${notice.auditEntryId}): e-mail to the athlete not sent yet (#218)`);
  }
}
