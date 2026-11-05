import { randomUUID } from "node:crypto";
import { ForbiddenException, Injectable, Logger } from "@nestjs/common";
import { EventEmitter2 } from "@nestjs/event-emitter";
import {
  ACCOUNT_DELETED_EVENT,
  ACCOUNT_DELETION_ERROR_CODES,
  type AccountDeletedEvent,
  type UserRole,
} from "@repo/contracts";
import { AuditService } from "@repo/core/audit";
import { AuthService } from "@repo/core/auth";
import { ModerationService } from "@repo/core/moderation";
import { EmailJobs } from "@repo/core/notifications";
import { SegmentsService } from "@repo/core/segments";
import { AccountJobs, UsersService } from "@repo/core/users";

/** The athlete deleting their own account, as their session tells it. */
export interface DeletingAthlete {
  userId: string;
  email: string;
  role: UserRole;
}

/** An Administrator's « Supprimer le compte » Sanction, recorded by the route's `@Audited`. */
export interface DeletionSanction {
  /** The Administrator's request headers: the admin plugin checks their session itself. */
  headers: Headers;
  userId: string;
  reason: string;
  /** The Journal entry `@Audited` writes: the e-mail's idempotency key. */
  auditEntryId: string;
  requestId?: string;
}

interface Deleted {
  userId: string;
  email: string;
  firstName: string | null;
  reason: string | null;
  idempotencyKey: string;
  requestId?: string;
}

/**
 * The one account deletion service (ADR-038 §13), called from the app and from the backoffice:
 * immediate and final, synchronous.
 *
 * 1. The notes of the Reports the athlete sent are erased (`moderation`); the Reports and their
 *    cases stay, `reporter_id` set to null by the foreign key.
 * 2. Sessions revoked and the `user` row deleted (`auth`); the SQL cascade erases account,
 *    profile, Activities and traces, Media, comments and kudos, Follows, Blocks, Efforts,
 *    Itineraries, favourite Segments and the local subscription. No denormalized counter exists
 *    to recompute: every count is computed on read. Just before, the Segments the athlete created
 *    that nobody else has an Effort on are deleted (`segments`, ADR-039 §11); the others stay
 *    with `created_by` set to null by the foreign key, nothing replayed for anyone.
 * 3. The Journal entry « Compte supprimé » (`user.delete`): by `@Audited` for a Sanction, here
 *    without author for the athlete. Ids only, never the e-mail or the name.
 * 4. The e-mail « Votre compte Nervo a été supprimé » (`emails` queue) and the `delete-account`
 *    job (`accounts` queue: bucket, RevenueCat, PostHog), with what they need since the account
 *    is gone; then `users.account.deleted` (#213 closes the cases about the athlete).
 *
 * Once the account is deleted nothing throws: a failure of step 3 or 4 is logged, the job and
 * the e-mail are retryable from the Jobs screen.
 */
@Injectable()
export class AccountDeletion {
  private readonly logger = new Logger(AccountDeletion.name);

  constructor(
    private readonly auth: AuthService,
    private readonly users: UsersService,
    private readonly moderation: ModerationService,
    private readonly segments: SegmentsService,
    private readonly audit: AuditService,
    private readonly emails: EmailJobs,
    private readonly accountJobs: AccountJobs,
    private readonly events: EventEmitter2,
  ) {}

  /** Sends the Sign-in code that confirms the deletion. `403` for an Administrator. */
  async requestCode(athlete: DeletingAthlete): Promise<void> {
    refuseAdministrator(athlete);
    await this.auth.sendAccountDeletionCode(athlete.email);
  }

  /** The athlete's own deletion, once their code checks out (`400` otherwise). `403` for an Administrator. */
  async deleteOwn(athlete: DeletingAthlete, code: string, requestId?: string): Promise<void> {
    refuseAdministrator(athlete);
    await this.auth.checkAccountDeletionCode(athlete.email, code);
    const firstName = await this.firstNameOf(athlete.userId);
    await this.moderation.eraseNotesOfReporter(athlete.userId);
    await this.segments.deleteSegmentsOnlyTheirs(athlete.userId);
    await this.auth.removeOwnAccount(athlete.userId);

    const entryId = randomUUID();
    try {
      await this.audit.record({
        id: entryId,
        actorId: null,
        action: "user.delete",
        targetId: athlete.userId,
        subjectUserId: athlete.userId,
        reason: null,
        details: { origin: "athlete" },
        requestId: requestId ?? null,
      });
    } catch (error) {
      this.logger.error(`Audit entry of the deletion of ${athlete.userId} not written: ${String(error)}`);
    }
    await this.afterDeletion(
      { userId: athlete.userId, email: athlete.email, firstName, reason: null, idempotencyKey: entryId, requestId },
      false,
    );
  }

  /**
   * « Supprimer le compte », a Sanction: `404 user_not_found`, `409 user_is_admin` before
   * anything is erased.
   */
  async deleteAsSanction(sanction: DeletionSanction): Promise<void> {
    const account = await this.auth.getAccountForAdmin(sanction.userId);
    const firstName = await this.firstNameOf(sanction.userId);
    if (account.role !== "admin") {
      await this.moderation.eraseNotesOfReporter(sanction.userId);
      await this.segments.deleteSegmentsOnlyTheirs(sanction.userId);
    }
    // Refuses an Administrator itself (`409`), before deleting anything.
    await this.auth.removeUser(sanction.headers, sanction.userId);
    await this.afterDeletion(
      {
        userId: sanction.userId,
        email: account.email,
        firstName,
        reason: sanction.reason,
        idempotencyKey: sanction.auditEntryId,
        requestId: sanction.requestId,
      },
      true,
    );
  }

  private async firstNameOf(userId: string): Promise<string | null> {
    const profile = await this.users.getAdminProfile(userId);
    return profile.firstName?.trim() || null;
  }

  private async afterDeletion(deleted: Deleted, bySanction: boolean): Promise<void> {
    const { userId, requestId } = deleted;
    try {
      await this.emails.enqueue({
        template: "account-deleted",
        to: deleted.email,
        idempotencyKey: deleted.idempotencyKey,
        userId,
        ...(requestId ? { requestId } : {}),
        data: { firstName: deleted.firstName, reason: deleted.reason },
      });
    } catch (error) {
      this.logger.error(`E-mail of the deletion of ${userId} not enqueued: ${String(error)}`);
    }
    try {
      await this.accountJobs.enqueueDeletion({ userId, ...(requestId ? { requestId } : {}) });
    } catch (error) {
      this.logger.error(`Cleanup of the deleted account ${userId} not enqueued: ${String(error)}`);
    }
    const event: AccountDeletedEvent = { userId, bySanction };
    try {
      this.events.emit(ACCOUNT_DELETED_EVENT, event);
    } catch (error) {
      this.logger.error(`${ACCOUNT_DELETED_EVENT} for ${userId} failed: ${String(error)}`);
    }
  }
}

function refuseAdministrator(athlete: DeletingAthlete): void {
  if (athlete.role === "admin") {
    throw new ForbiddenException({
      code: ACCOUNT_DELETION_ERROR_CODES.adminCannotDelete,
      message: "Un administrateur ne peut pas supprimer son compte",
    });
  }
}
