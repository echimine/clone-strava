import { ConflictException, Inject, Injectable } from "@nestjs/common";
import { ADMIN_USER_ERROR_CODES, signInMethodsFromProviders, type SignInMethod, type UserRole } from "@repo/contracts";
import { AUTH_INSTANCE } from "./auth.constants.js";
import type { AuthInstance } from "./auth-instance.type.js";
import { SESSION_AUTH_METHODS, type SessionAuthMethod } from "./domain/session-auth-method.js";
import type { InstantRange } from "../infrastructure/index.js";
import { AuthAdminStatsRepository } from "./repositories/auth-admin-stats.repository.js";
import { AuthUserRepository } from "./repositories/auth-user.repository.js";
import { activeBan, type ActiveBan } from "./domain/ban.js";
import { AccountReader } from "./services/account-reader.js";
import { AccountRemover } from "./services/account-remover.js";
import { AuthAdminApi, type AdminSessionRecord } from "./services/auth-admin-api.js";
import { BackfillGoogleAvatarsUseCase } from "./use-cases/backfill-google-avatars.use-case.js";
import { BanUserUseCase } from "./use-cases/ban-user.use-case.js";
import { SetUserRoleUseCase } from "./use-cases/set-user-role.use-case.js";

export type { ActiveBan } from "./domain/ban.js";
export type { AdminSessionRecord } from "./services/auth-admin-api.js";

/** An account as the backoffice user sheet shows it (ADR-038 §5). */
export interface AdminAccount {
  id: string;
  email: string;
  name: string;
  role: UserRole;
  createdAt: Date;
  twoFactorEnabled: boolean;
  /** The Ban in force, if any. */
  ban: ActiveBan | null;
  signInMethods: SignInMethod[];
}

/**
 * Current session, as read from Better Auth (ADR-009 §3: used by
 * `GET /v1/me`, guards). `email`/`name` come straight from Better Auth's
 * own `user` table (ADR-017); `GET /v1/me` (ADR-009 §3) needs both, on top
 * of `role` and `SubscriptionsService.isPremium`.
 */
export interface AuthSession {
  userId: string;
  email: string;
  name: string;
  role: UserRole;
  /** Added by the `twoFactor` plugin (ADR-022 §5): required for `AdminGuard`. */
  twoFactorEnabled: boolean;
  /**
   * How this session was opened (ADR-035 §3): `AdminGuard` requires
   * `password_2fa`. `null` for sessions opened before the field existed or
   * by an unknown path; they count as weak.
   */
  authMethod: SessionAuthMethod | null;
}

/**
 * Name an account shows to other users (ADR-029): the fallback of
 * `UsersService.getSummaries` while `user_profile` has no name. Better Auth's
 * `user.image` is not part of it: the Avatar lives in `users` (ADR-037 §2).
 */
export interface PublicIdentity {
  userId: string;
  name: string;
}

/**
 * Public facade of the `auth` module (ADR-021 §1, layer 0). Wraps the
 * Better Auth instance so other modules and apps never import
 * `AUTH_INSTANCE` directly (ADR-021 §6 "Public API = index.ts").
 */
@Injectable()
export class AuthService {
  constructor(
    private readonly adminStats: AuthAdminStatsRepository,
    @Inject(AUTH_INSTANCE) private readonly auth: AuthInstance,
    private readonly users: AuthUserRepository,
    private readonly backfillGoogleAvatars: BackfillGoogleAvatarsUseCase,
    private readonly accounts: AccountReader,
    private readonly adminApi: AuthAdminApi,
    private readonly banUserUseCase: BanUserUseCase,
    private readonly setUserRoleUseCase: SetUserRoleUseCase,
    private readonly remover: AccountRemover,
  ) {}

  // --- Backoffice (ADR-038 §5, §6). `headers` are the Administrator's request headers: the
  // admin plugin checks their session itself. `404 user_not_found` for an unknown account. ---

  /** The account part of the user sheet. */
  async getAccountForAdmin(userId: string): Promise<AdminAccount> {
    const account = await this.accounts.get(userId);
    return {
      id: account.id,
      email: account.email,
      name: account.name,
      role: account.role,
      createdAt: account.createdAt,
      twoFactorEnabled: account.twoFactorEnabled,
      ban: activeBan(account, new Date()),
      signInMethods: signInMethodsFromProviders(account.providerIds),
    };
  }

  /**
   * Bans `userId` for `expiresInSeconds` (null = permanent) and revokes their sessions; banning
   * again replaces the duration. `409 user_is_admin` for an Administrator. Returns the Ban.
   */
  banUser(headers: Headers, userId: string, reason: string, expiresInSeconds: number | null): Promise<ActiveBan> {
    return this.banUserUseCase.execute(headers, userId, reason, expiresInSeconds);
  }

  /** Lifts the Ban at once; `409 not_banned` without an active one. Returns the Ban lifted. */
  async unbanUser(headers: Headers, userId: string): Promise<ActiveBan> {
    const ban = activeBan(await this.accounts.get(userId), new Date());
    if (!ban) {
      throw new ConflictException({ code: ADMIN_USER_ERROR_CODES.notBanned, message: "The account is not banned" });
    }
    await this.adminApi.unban(headers, userId);
    return ban;
  }

  /** « Déconnecter partout »: every session closes; the athlete can sign in again at once. */
  async revokeUserSessions(headers: Headers, userId: string): Promise<void> {
    await this.accounts.get(userId);
    await this.adminApi.revokeSessions(headers, userId);
  }

  /** Grants or removes the `admin` role; `409` for no change, a self-demotion or the last Administrator. */
  setRole(headers: Headers, actorId: string, userId: string, role: UserRole): Promise<void> {
    return this.setUserRoleUseCase.execute(headers, actorId, userId, role);
  }

  /** The account's open sessions, newest first. */
  async listUserSessions(headers: Headers, userId: string): Promise<AdminSessionRecord[]> {
    await this.accounts.get(userId);
    const sessions = await this.adminApi.listSessions(headers, userId);
    return sessions.sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime());
  }

  /**
   * Sanction « Supprimer le compte » (ADR-038 §13): sessions revoked and the account removed
   * through the admin plugin. `409 user_is_admin` for an Administrator, `404 user_not_found`.
   */
  removeUser(headers: Headers, userId: string): Promise<void> {
    return this.remover.removeAsAdmin(headers, userId);
  }

  // --- Account deletion by the athlete (ADR-038 §13) ---

  /** Sends a Sign-in code to `email`, the account's own, to re-verify the athlete. */
  sendAccountDeletionCode(email: string): Promise<void> {
    return this.remover.sendCode(email);
  }

  /** Checks and spends that code: `400 invalid_code` / `code_expired` / `too_many_attempts`. */
  checkAccountDeletionCode(email: string, code: string): Promise<void> {
    return this.remover.checkCode(email, code);
  }

  /** Revokes every session of `userId` and deletes the account; the SQL cascade does the rest. */
  removeOwnAccount(userId: string): Promise<void> {
    return this.remover.removeOwn(userId);
  }

  /** Every Administrator (`role = admin`): the accounts the backoffice stats leave out (ADR-038 §15). */
  listAdminIds(): Promise<string[]> {
    return this.adminStats.findAdminIds();
  }

  /** Backoffice dashboard (ADR-038 §15): sign-ups per Paris day of `range`, Administrators left out. */
  countSignUpsPerParisDay(range: InstantRange): Promise<Map<string, number>> {
    return this.adminStats.countSignUpsPerParisDay(range);
  }

  /** Batch read (ADR-021 §2 rule 6): feed authors (ADR-029). */
  async getPublicIdentities(userIds: string[]): Promise<PublicIdentity[]> {
    const rows = await this.users.findPublicByIds([...new Set(userIds)]);
    return rows.map((row) => ({ userId: row.id, name: row.name }));
  }

  /**
   * The one-off Google photo backfill (ADR-037 §2): enqueues the copy of the photo of every
   * existing Google account; the worker copies it only for athletes still without an Avatar.
   * Replayable. Returns the number of jobs enqueued.
   */
  backfillGoogleAvatarCopies(): Promise<number> {
    return this.backfillGoogleAvatars.execute();
  }

  /** `ADR-009 §3`: session guard, `GET /v1/me`. `headers` is the incoming request's `Headers`. */
  async getSession(headers: Headers): Promise<AuthSession | null> {
    const result = await this.auth.api.getSession({ headers });
    if (!result) {
      return null;
    }
    return {
      userId: result.user.id,
      email: result.user.email,
      name: result.user.name,
      role: result.user.role as UserRole,
      twoFactorEnabled: Boolean(result.user.twoFactorEnabled),
      authMethod: SESSION_AUTH_METHODS.find((method) => method === result.session.authMethod) ?? null,
    };
  }

  /**
   * Sets the account's `user.name` (ADR-036 §3: kept equal to the profile's "Prénom Nom" so the
   * backoffice and emails agree). Goes through Better Auth's `internalAdapter`, as below, so its
   * session cache sees the change.
   */
  async setName(userId: string, name: string): Promise<void> {
    const context = await this.auth.$context;
    await context.internalAdapter.updateUser(userId, { name });
  }

  /**
   * Flags `email` as unverified (ADR-023: `ResendWebhookController` calls
   * this on `email.bounced`/`email.complained`). Goes through Better Auth's
   * own `internalAdapter` (via `$context`, not the HTTP `api`) since this is
   * a system-triggered update with no admin session to satisfy the `admin`
   * plugin's `updateUser` permission check.
   */
  async markEmailUnverified(email: string): Promise<void> {
    const context = await this.auth.$context;
    await context.internalAdapter.updateUserByEmail(email, { emailVerified: false });
  }
}
