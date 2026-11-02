import { CanActivate, type ExecutionContext, ForbiddenException, Injectable } from "@nestjs/common";
import { ADMIN_ACCESS_ERROR_CODES } from "@repo/contracts";
import type { Request } from "express";
import type { AuthenticatedUser } from "./session.guard.js";

/**
 * Protects `/v1/admin/*` routes (ADR-004, ADR-009 §3). Must run after
 * `SessionGuard` (which attaches `request.user`): both are applied together
 * with `@UseGuards(SessionGuard, AdminGuard)`.
 *
 * Refuses, in this order:
 * - not an admin: plain `403`;
 * - 2FA not enabled (ADR-022 §5): `ADMIN_2FA_REQUIRED`. The `twoFactor`
 *   plugin adds `twoFactorEnabled` straight to `user`, so no separate flag;
 * - a session not opened by password + second factor (ADR-035 §3, amends
 *   ADR-022 §5): `ADMIN_STRONG_SESSION_REQUIRED`. The limit is on the
 *   session, not the account: the same admin's Sign-in code or Google
 *   session keeps working on app routes. Google has no exception any more,
 *   and sessions without `authMethod` (opened before it existed) count as
 *   weak.
 */
@Injectable()
export class AdminGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest<Request & { user?: AuthenticatedUser }>();
    if (request.user?.role !== "admin") {
      throw new ForbiddenException();
    }
    if (!request.user.twoFactorEnabled) {
      throw new ForbiddenException({
        code: ADMIN_ACCESS_ERROR_CODES.twoFactorRequired,
        message: "Two-factor authentication is required for admin accounts.",
      });
    }
    if (request.user.authMethod !== "password_2fa") {
      throw new ForbiddenException({
        code: ADMIN_ACCESS_ERROR_CODES.strongSessionRequired,
        message: "Sign in again on the backoffice with your password and second factor.",
      });
    }
    return true;
  }
}
