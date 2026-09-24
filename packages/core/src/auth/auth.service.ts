import { Inject, Injectable } from "@nestjs/common";
import type { UserRole } from "@repo/contracts";
import { AUTH_INSTANCE } from "./auth.constants.js";
import type { AuthInstance } from "./auth-instance.type.js";

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
}

/**
 * Public facade of the `auth` module (ADR-021 §1, layer 0). Wraps the
 * Better Auth instance so other modules and apps never import
 * `AUTH_INSTANCE` directly (ADR-021 §6 "Public API = index.ts").
 */
@Injectable()
export class AuthService {
  constructor(@Inject(AUTH_INSTANCE) private readonly auth: AuthInstance) {}

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
    };
  }
}
