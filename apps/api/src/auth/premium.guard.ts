import { CanActivate, type ExecutionContext, ForbiddenException, Injectable } from "@nestjs/common";
import type { Request } from "express";
import { SubscriptionsService } from "@repo/core/subscriptions";
import type { AuthenticatedUser } from "./session.guard.js";

/**
 * Premium-only routes (ADR-014 §5): creating an Itinerary or a Segment (ADR-030 §6 and ADR-039
 * §9, amended 2026-11-06). Runs after `SessionGuard`; without Premium, `403 premium_required`.
 * The status is read from the database at each call, so an expired Premium closes at once.
 */
@Injectable()
export class PremiumGuard implements CanActivate {
  constructor(private readonly subscriptions: SubscriptionsService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<Request & { user?: AuthenticatedUser }>();
    if (!request.user) {
      // Wiring bug: `SessionGuard` always runs first on the class.
      throw new Error("PremiumGuard used on a route without SessionGuard");
    }
    if (!(await this.subscriptions.isPremium(request.user.userId))) {
      throw new ForbiddenException({ code: "premium_required", message: "Premium is required" });
    }
    return true;
  }
}
