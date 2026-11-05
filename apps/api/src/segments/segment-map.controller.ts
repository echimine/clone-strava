import { BadRequestException, Controller, Get, Query, UseGuards } from "@nestjs/common";
import { ApiResponse } from "@nestjs/swagger";
import { createZodDto, ZodResponse } from "nestjs-zod";
import {
  isSegmentMapZoneTooLarge,
  listMapSegmentsQuerySchema,
  listMapSegmentsResponseSchema,
  SEGMENT_MAP_MAX_RESULTS,
  type ListMapSegmentsResponse,
} from "@repo/contracts";
import { SegmentsService } from "@repo/core/segments";
import { CurrentUser } from "../auth/current-user.decorator.js";
import { SessionGuard, type AuthenticatedUser } from "../auth/session.guard.js";
import { ViewerFilter } from "../viewer-filter/viewer-filter.js";

class ListMapSegmentsQueryDto extends createZodDto(listMapSegmentsQuerySchema) {}
class ListMapSegmentsResponseDto extends createZodDto(listMapSegmentsResponseSchema) {}

/** `GET /v1/segments` (ADR-039 §12, §15): the Segments mode of the Map tab. */
@Controller("segments")
@UseGuards(SessionGuard)
export class SegmentMapController {
  constructor(
    private readonly segments: SegmentsService,
    private readonly viewerFilter: ViewerFilter,
  ) {}

  /**
   * At most 50 Segments crossing `bbox`, the most athletes first. `422` invalid `bbox`,
   * `400 zone_too_large` beyond what a screen shows at zoom 10.5.
   */
  @Get()
  @ZodResponse({ status: 200, type: ListMapSegmentsResponseDto })
  @ApiResponse({ status: 400, description: "zone_too_large" })
  async list(
    @Query() query: ListMapSegmentsQueryDto,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<ListMapSegmentsResponse> {
    if (isSegmentMapZoneTooLarge(query.bbox)) {
      throw new BadRequestException({ code: "zone_too_large", message: "Zoom in to see the Segments" });
    }
    const exclusions = await this.viewerFilter.for(user.userId);
    const items = await this.segments.findOnMap(
      {
        viewerId: user.userId,
        bbox: query.bbox,
        sportTypeCode: query.sport,
        favoritesOnly: query.favorites,
        limit: SEGMENT_MAP_MAX_RESULTS,
      },
      exclusions,
    );
    return { items } as ListMapSegmentsResponse;
  }
}
