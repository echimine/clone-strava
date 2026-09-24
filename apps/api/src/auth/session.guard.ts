import { CanActivate, type ExecutionContext, Injectable, UnauthorizedException } from "@nestjs/common";
import { fromNodeHeaders } from "better-auth/node";
import type { Request } from "express";
import { AuthService, type AuthSession } from "@repo/core/auth";

export type AuthenticatedUser = AuthSession;

/**
 * Checks the Better Auth session on protected routes (ADR-009 §3), via
 * `@repo/core/auth`'s `AuthService`. Accepts both the cookie (backoffice)
 * and the `Authorization: Bearer` token (iOS, via the `bearer` plugin),
 * since both flow through the same session lookup inside
 * `auth.api.getSession`.
 */
@Injectable()
export class SessionGuard implements CanActivate {
  constructor(private readonly authService: AuthService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<Request & { user?: AuthenticatedUser }>();

    const session = await this.authService.getSession(fromNodeHeaders(request.headers));
    if (!session) {
      throw new UnauthorizedException();
    }

    request.user = session;
    return true;
  }
}
