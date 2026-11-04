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
import { ViewerFilter } from "../viewer-filter/viewer-filter.js";
import { KudosAssembler } from "./kudos-assembler.js";

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
    private readonly assembler: KudosAssembler,
    private readonly viewerFilter: ViewerFilter,
  ) {}

  /**
   * Most recent first, keyset pages; a cursor this server did not produce is `422
   * invalid_cursor`. Athletes hidden from the viewer are left out (ADR-038 §7).
   */
  @Get()
  @ZodResponse({ status: 200, type: ListKudosResponseDto })
  async list(
    @Param("id", ParseUUIDPipe) activityId: string,
    @Query() query: ListKudosQueryDto,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<ListKudosResponse> {
    const filter = await this.viewerFilter.for(user.userId);
    return this.assembler.assemble(await this.engagement.listKudos(user.userId, activityId, query, filter));
  }

  @Put()
  @ZodResponse({ status: 200, type: KudosResponseDto })
  async give(
    @Param("id", ParseUUIDPipe) activityId: string,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<KudosResponse> {
    return this.engagement.giveKudos(user.userId, activityId, await this.viewerFilter.for(user.userId));
  }

  @Delete()
  @ZodResponse({ status: 200, type: KudosResponseDto })
  async remove(
    @Param("id", ParseUUIDPipe) activityId: string,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<KudosResponse> {
    return this.engagement.removeKudos(user.userId, activityId, await this.viewerFilter.for(user.userId));
  }
}
