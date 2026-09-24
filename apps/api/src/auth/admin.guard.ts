import { CanActivate, type ExecutionContext, ForbiddenException, Injectable } from "@nestjs/common";
import type { Request } from "express";
import type { AuthenticatedUser } from "./session.guard.js";

/**
 * Protects `/v1/admin/*` routes (ADR-004, ADR-009 §3). Must run after
 * `SessionGuard` (which attaches `request.user`): both are applied together
 * with `@UseGuards(SessionGuard, AdminGuard)`.
 */
@Injectable()
export class AdminGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest<Request & { user?: AuthenticatedUser }>();
    if (request.user?.role !== "admin") {
      throw new ForbiddenException();
    }
    return true;
  }
}
