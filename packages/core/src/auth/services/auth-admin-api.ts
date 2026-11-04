import { HttpException, Inject, Injectable } from "@nestjs/common";
import type { UserRole } from "@repo/contracts";
import { isAPIError } from "better-auth/api";
import { AUTH_INSTANCE } from "../auth.constants.js";
import type { AuthInstance } from "../auth-instance.type.js";

/** An open session as the admin plugin lists it (never its token). */
export interface AdminSessionRecord {
  id: string;
  userAgent: string | null;
  createdAt: Date;
  expiresAt: Date;
}

/**
 * The admin plugin's server-side calls (ADR-038 §1): Ban, unban, sign-out, role and sessions go
 * through `auth.api.*` with the Administrator's request headers, never a direct write, so the
 * plugin keeps its own checks and revokes the sessions itself. No `request` is passed, so the
 * `user.update` hook records nothing: the backoffice route is `@Audited` itself.
 *
 * Better Auth's `APIError`s become our `{ code, message }` (`USER_NOT_FOUND` → `404 user_not_found`).
 */
@Injectable()
export class AuthAdminApi {
  constructor(@Inject(AUTH_INSTANCE) private readonly auth: AuthInstance) {}

  async ban(headers: Headers, userId: string, reason: string, expiresInSeconds: number | null): Promise<void> {
    await translated(() =>
      this.auth.api.banUser({
        body: { userId, banReason: reason, ...(expiresInSeconds === null ? {} : { banExpiresIn: expiresInSeconds }) },
        headers,
      }),
    );
  }

  async unban(headers: Headers, userId: string): Promise<void> {
    await translated(() => this.auth.api.unbanUser({ body: { userId }, headers }));
  }

  async revokeSessions(headers: Headers, userId: string): Promise<void> {
    await translated(() => this.auth.api.revokeUserSessions({ body: { userId }, headers }));
  }

  async setRole(headers: Headers, userId: string, role: UserRole): Promise<void> {
    await translated(() => this.auth.api.setRole({ body: { userId, role }, headers }));
  }

  async listSessions(headers: Headers, userId: string): Promise<AdminSessionRecord[]> {
    const { sessions } = await translated(() => this.auth.api.listUserSessions({ body: { userId }, headers }));
    return sessions.map((session) => ({
      id: session.id,
      userAgent: session.userAgent ?? null,
      createdAt: new Date(session.createdAt),
      expiresAt: new Date(session.expiresAt),
    }));
  }
}

async function translated<T>(call: () => Promise<T>): Promise<T> {
  try {
    return await call();
  } catch (error) {
    if (isAPIError(error)) {
      const body = (error.body ?? {}) as { code?: unknown; message?: unknown };
      const code = typeof body.code === "string" ? body.code.toLowerCase() : "auth_error";
      const message = typeof body.message === "string" ? body.message : error.message;
      throw new HttpException({ code, message }, error.statusCode);
    }
    throw error;
  }
}
