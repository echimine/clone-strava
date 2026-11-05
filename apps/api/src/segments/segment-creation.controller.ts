import { Controller, Delete, HttpCode, HttpStatus, Param, ParseUUIDPipe, Put, UseGuards } from "@nestjs/common";
import { ApiResponse } from "@nestjs/swagger";
import { SegmentsService } from "@repo/core/segments";
import { CurrentUser } from "../auth/current-user.decorator.js";
import { SessionGuard, type AuthenticatedUser } from "../auth/session.guard.js";

/**
 * Minimal version written by #250 (the Map card's star) with #249's signature: #249 owns this
 * controller (creation, rename, deletion, favourites) and its version wins at the merge.
 */
@Controller()
@UseGuards(SessionGuard)
export class SegmentCreationController {
  constructor(private readonly segments: SegmentsService) {}

  /** Stars a Segment (ADR-039 §5), idempotent. `404 segment_not_found`. */
  @Put("segments/:id/favorite")
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiResponse({ status: 204, description: "Starred" })
  favorite(@Param("id", ParseUUIDPipe) segmentId: string, @CurrentUser() user: AuthenticatedUser): Promise<void> {
    return this.segments.favorite(user.userId, segmentId);
  }

  /** Unstars a Segment, idempotent. `404 segment_not_found`. */
  @Delete("segments/:id/favorite")
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiResponse({ status: 204, description: "Unstarred" })
  unfavorite(@Param("id", ParseUUIDPipe) segmentId: string, @CurrentUser() user: AuthenticatedUser): Promise<void> {
    return this.segments.unfavorite(user.userId, segmentId);
  }
}
