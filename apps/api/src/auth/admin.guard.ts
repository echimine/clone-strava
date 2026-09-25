import { CanActivate, type ExecutionContext, ForbiddenException, Injectable } from "@nestjs/common";
import type { Request } from "express";
import type { AuthenticatedUser } from "./session.guard.js";

/**
 * Protects `/v1/admin/*` routes (ADR-004, ADR-009 §3). Must run after
 * `SessionGuard` (which attaches `request.user`): both are applied together
 * with `@UseGuards(SessionGuard, AdminGuard)`.
 *
 * ADR-022 §5: 2FA is mandatory for admins. The `twoFactor` plugin adds
 * `twoFactorEnabled` straight to `user`, so no separate "2FA required" flag
 * is needed — an admin who hasn't enabled it yet is blocked with a
 * greppable `ADMIN_2FA_REQUIRED` code until they do.
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
        code: "ADMIN_2FA_REQUIRED",
        message: "Two-factor authentication is required for admin accounts.",
      });
    }
    return true;
  }
}
