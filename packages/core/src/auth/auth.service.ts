import { Inject, Injectable } from "@nestjs/common";
import type { UserRole } from "@repo/contracts";
import { AUTH_INSTANCE } from "./auth.constants.js";
import type { AuthInstance } from "./auth-instance.type.js";
import { SESSION_AUTH_METHODS, type SessionAuthMethod } from "./domain/session-auth-method.js";
import { AuthUserRepository } from "./repositories/auth-user.repository.js";

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
 * Name and picture an account shows to other users (ADR-029): the fallback
 * of `UsersService.getSummaries` while `user_profile` rows are not created.
 */
export interface PublicIdentity {
  userId: string;
  name: string;
  image: string | null;
}

/**
 * Public facade of the `auth` module (ADR-021 §1, layer 0). Wraps the
 * Better Auth instance so other modules and apps never import
 * `AUTH_INSTANCE` directly (ADR-021 §6 "Public API = index.ts").
 */
@Injectable()
export class AuthService {
  constructor(
    @Inject(AUTH_INSTANCE) private readonly auth: AuthInstance,
    private readonly users: AuthUserRepository,
  ) {}

  /** Batch read (ADR-021 §2 rule 6): feed authors (ADR-029). */
  async getPublicIdentities(userIds: string[]): Promise<PublicIdentity[]> {
    const rows = await this.users.findPublicByIds([...new Set(userIds)]);
    return rows.map((row) => ({ userId: row.id, name: row.name, image: row.image ?? null }));
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
