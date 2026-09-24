import { createParamDecorator, type ExecutionContext } from "@nestjs/common";
import type { Request } from "express";
import type { AuthenticatedUser } from "./session.guard.js";

/** Injects the current user attached by `SessionGuard` (ADR-009 §3). */
export const CurrentUser = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext): AuthenticatedUser => {
    const request = ctx.switchToHttp().getRequest<Request & { user?: AuthenticatedUser }>();
    if (!request.user) {
      // SessionGuard always runs first on any route using @CurrentUser(); a
      // missing user here is a wiring bug, not an auth failure.
      throw new Error("CurrentUser used on a route without SessionGuard");
    }
    return request.user;
  },
);
