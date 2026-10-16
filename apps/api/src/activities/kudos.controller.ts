import { Controller, Delete, Get, Param, ParseUUIDPipe, Put, Query, UseGuards } from "@nestjs/common";
import { createZodDto, ZodResponse } from "nestjs-zod";
import {
  kudosResponseSchema,
  listKudosQuerySchema,
  listKudosResponseSchema,
  type KudosResponse,
  type ListKudosResponse,
} from "@repo/contracts";
import { EngagementService } from "@repo/core/engagement";
import { CurrentUser } from "../auth/current-user.decorator.js";
import { SessionGuard, type AuthenticatedUser } from "../auth/session.guard.js";
import { AthleteIdentities } from "../identities/athlete-identities.js";

class KudosResponseDto extends createZodDto(kudosResponseSchema) {}
class ListKudosQueryDto extends createZodDto(listKudosQuerySchema) {}
class ListKudosResponseDto extends createZodDto(listKudosResponseSchema) {}

/**
 * `/v1/activities/:id/kudos`: who gave kudos (ADR-034 §1), idempotent give
 * (`PUT`) and remove (`DELETE`), both returning the authoritative count
 * (ADR-029). `404 activity_not_found` when the activity is not visible,
 * `422 cannot_kudos_own_activity`.
 */
@Controller("activities/:id/kudos")
@UseGuards(SessionGuard)
export class KudosController {
  constructor(
    private readonly engagement: EngagementService,
    private readonly identities: AthleteIdentities,
  ) {}

  /** Most recent first, keyset pages; a cursor this server did not produce is `422 invalid_cursor`. */
  @Get()
  @ZodResponse({ status: 200, type: ListKudosResponseDto })
  async list(
    @Param("id", ParseUUIDPipe) activityId: string,
    @Query() query: ListKudosQueryDto,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<ListKudosResponse> {
    const page = await this.engagement.listKudos(user.userId, activityId, query);
    const athlete = await this.identities.resolve(page.items.map((item) => item.athleteId));
    return {
      items: page.items.map((item) => ({ athlete: athlete(item.athleteId), givenAt: item.givenAt.toISOString() })),
      nextCursor: page.nextCursor,
    };
  }

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
