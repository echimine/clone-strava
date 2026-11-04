import { Controller, Get, Query, UseGuards } from "@nestjs/common";
import { createZodDto, ZodResponse } from "nestjs-zod";
import { feedQuerySchema, feedResponseSchema, type FeedResponse } from "@repo/contracts";
import { ActivitiesService } from "@repo/core/activities";
import { CurrentUser } from "../auth/current-user.decorator.js";
import { SessionGuard, type AuthenticatedUser } from "../auth/session.guard.js";
import { ViewerFilter } from "../viewer-filter/viewer-filter.js";
import { FeedAssembler } from "./feed-assembler.js";

class FeedQueryDto extends createZodDto(feedQuerySchema) {}
class FeedResponseDto extends createZodDto(feedResponseSchema) {}

/** `GET /v1/feed` (ADR-029): the viewer's and their followees' activities, newest first. */
@Controller("feed")
@UseGuards(SessionGuard)
export class FeedController {
  constructor(
    private readonly activities: ActivitiesService,
    private readonly assembler: FeedAssembler,
    private readonly viewerFilter: ViewerFilter,
  ) {}

  @Get()
  @ZodResponse({ status: 200, type: FeedResponseDto })
  async list(@Query() query: FeedQueryDto, @CurrentUser() user: AuthenticatedUser): Promise<FeedResponse> {
    const filter = await this.viewerFilter.for(user.userId);
    const page = await this.activities.getFeedPage(user.userId, query, filter);
    return { items: await this.assembler.assemble(user.userId, page.items, filter), nextCursor: page.nextCursor };
  }
}
