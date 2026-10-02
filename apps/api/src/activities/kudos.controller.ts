import { Controller, Delete, Param, ParseUUIDPipe, Put, UseGuards } from "@nestjs/common";
import { createZodDto, ZodResponse } from "nestjs-zod";
import { kudosResponseSchema, type KudosResponse } from "@repo/contracts";
import { EngagementService } from "@repo/core/engagement";
import { CurrentUser } from "../auth/current-user.decorator.js";
import { SessionGuard, type AuthenticatedUser } from "../auth/session.guard.js";

class KudosResponseDto extends createZodDto(kudosResponseSchema) {}

/**
 * `/v1/activities/:id/kudos` (ADR-029): idempotent give (`PUT`) and remove
 * (`DELETE`), both returning the authoritative count. `404` when the
 * activity is not visible, `422 cannot_kudos_own_activity`.
 */
@Controller("activities/:id/kudos")
@UseGuards(SessionGuard)
export class KudosController {
  constructor(private readonly engagement: EngagementService) {}

  @Put()
  @ZodResponse({ status: 200, type: KudosResponseDto })
  give(@Param("id", ParseUUIDPipe) activityId: string, @CurrentUser() user: AuthenticatedUser): Promise<KudosResponse> {
    return this.engagement.giveKudos(user.userId, activityId);
  }

  @Delete()
  @ZodResponse({ status: 200, type: KudosResponseDto })
  remove(
    @Param("id", ParseUUIDPipe) activityId: string,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<KudosResponse> {
    return this.engagement.removeKudos(user.userId, activityId);
  }
}
