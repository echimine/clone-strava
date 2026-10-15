import { Controller, Get, UseGuards } from "@nestjs/common";
import { createZodDto, ZodResponse } from "nestjs-zod";
import { meResponseSchema, type MeResponse } from "@repo/contracts";
import { SubscriptionsService } from "@repo/core/subscriptions";
import { UsersService } from "@repo/core/users";
import { CurrentUser } from "../auth/current-user.decorator.js";
import { SessionGuard } from "../auth/session.guard.js";
import type { AuthenticatedUser } from "../auth/session.guard.js";

class MeResponseDto extends createZodDto(meResponseSchema) {}

/** `GET /v1/me` (ADR-009 §3, ADR-031 §13): current user, role, premium status and default visibility. */
@Controller("me")
@UseGuards(SessionGuard)
export class MeController {
  constructor(
    private readonly subscriptionsService: SubscriptionsService,
    private readonly usersService: UsersService,
  ) {}

  @Get()
  @ZodResponse({ status: 200, type: MeResponseDto })
  async get(@CurrentUser() user: AuthenticatedUser): Promise<MeResponse> {
    // `id`/`email`/`name`/`role` already come from the session (Better
    // Auth's own `user` table, ADR-017); only the premium status needs a
    // call to `subscriptions` (ADR-021 §5 batch reads / here a single read),
    // and the default visibility a read of `users`.
    const [isPremium, defaults] = await Promise.all([
      this.subscriptionsService.isPremium(user.userId),
      this.usersService.getActivityDefaults(user.userId),
    ]);
    return {
      id: user.userId,
      email: user.email,
      name: user.name,
      role: user.role,
      isPremium,
      defaultVisibility: defaults.defaultVisibility,
    };
  }
}
