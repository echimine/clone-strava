import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Put,
  Query,
  UseGuards,
} from "@nestjs/common";
import { ApiResponse } from "@nestjs/swagger";
import { createZodDto, ZodResponse } from "nestjs-zod";
import {
  createdSegmentSchema,
  createSegmentRequestSchema,
  listSegmentFavoritesQuerySchema,
  listSegmentFavoritesResponseSchema,
  previewSegmentRequestSchema,
  renameSegmentRequestSchema,
  segmentPreviewSchema,
  segmentRefSchema,
  type CreatedSegment,
  type ListSegmentFavoritesResponse,
  type SegmentPreview,
  type SegmentRef,
} from "@repo/contracts";
import { SegmentCreationService, SegmentsService } from "@repo/core/segments";
import { CurrentUser } from "../auth/current-user.decorator.js";
import { SessionGuard, type AuthenticatedUser } from "../auth/session.guard.js";

class PreviewSegmentRequestDto extends createZodDto(previewSegmentRequestSchema) {}
class SegmentPreviewDto extends createZodDto(segmentPreviewSchema) {}
class CreateSegmentRequestDto extends createZodDto(createSegmentRequestSchema) {}
class CreatedSegmentDto extends createZodDto(createdSegmentSchema) {}
class RenameSegmentRequestDto extends createZodDto(renameSegmentRequestSchema) {}
class SegmentRefDto extends createZodDto(segmentRefSchema) {}
class ListSegmentFavoritesQueryDto extends createZodDto(listSegmentFavoritesQuerySchema) {}
class ListSegmentFavoritesResponseDto extends createZodDto(listSegmentFavoritesResponseSchema) {}

/**
 * Creating a Segment in the app (spec #249, ADR-039 §5, §12): draw, preview, create, rename,
 * delete; and the star, with Plus › « Segments ».
 */
@Controller()
@UseGuards(SessionGuard)
export class SegmentCreationController {
  constructor(
    private readonly creation: SegmentCreationService,
    private readonly segments: SegmentsService,
  ) {}

  /**
   * Figures, profile and category of the drawn path, the rules it breaks, the duplicate (with
   * the existing Segment) and the creations left; writes nothing. `503` (retryable) when the
   * `ElevationService` fails.
   */
  @Post("segments/preview")
  @HttpCode(HttpStatus.OK)
  @ZodResponse({ status: 200, type: SegmentPreviewDto })
  preview(@Body() body: PreviewSegmentRequestDto, @CurrentUser() user: AuthenticatedUser): Promise<SegmentPreview> {
    return this.creation.preview(user.userId, body);
  }

  /**
   * Creates the Segment (everything recomputed), stars it for its creator and starts its
   * retro-matching. `409 duplicate` (with `existing`), `429 quota` (with
   * `Retry-After`), `422` `too_short`, `too_long`, `loop` or an invalid name, `503` (retryable).
   */
  @Post("segments")
  @ZodResponse({ status: 201, type: CreatedSegmentDto, description: "Created" })
  create(@Body() body: CreateSegmentRequestDto, @CurrentUser() user: AuthenticatedUser): Promise<CreatedSegment> {
    return this.creation.create(user.userId, body);
  }

  /** Renames, creator only (`403 not_creator`), no recomputation; `404` if unknown. */
  @Patch("segments/:id")
  @ZodResponse({ status: 200, type: SegmentRefDto })
  rename(
    @Param("id", ParseUUIDPipe) segmentId: string,
    @Body() body: RenameSegmentRequestDto,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<SegmentRef> {
    return this.segments.rename(user.userId, segmentId, body.name);
  }

  /** Final delete, creator only (`403`); `409 has_other_efforts` once someone else has an Effort. */
  @Delete("segments/:id")
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiResponse({ status: 204, description: "Deleted" })
  remove(@Param("id", ParseUUIDPipe) segmentId: string, @CurrentUser() user: AuthenticatedUser): Promise<void> {
    return this.segments.deleteOwn(user.userId, segmentId);
  }

  /** Stars the Segment; idempotent, `404 segment_not_found`. */
  @Put("segments/:id/favorite")
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiResponse({ status: 204, description: "Starred" })
  favorite(@Param("id", ParseUUIDPipe) segmentId: string, @CurrentUser() user: AuthenticatedUser): Promise<void> {
    return this.segments.favorite(user.userId, segmentId);
  }

  /** Unstars the Segment; idempotent, `404 segment_not_found`. */
  @Delete("segments/:id/favorite")
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiResponse({ status: 204, description: "Unstarred" })
  unfavorite(@Param("id", ParseUUIDPipe) segmentId: string, @CurrentUser() user: AuthenticatedUser): Promise<void> {
    return this.segments.unfavorite(user.userId, segmentId);
  }

  /** Plus › « Segments »: my starred Segments, most recently starred first (keyset cursor). */
  @Get("me/segment-favorites")
  @ZodResponse({ status: 200, type: ListSegmentFavoritesResponseDto })
  listFavorites(
    @Query() query: ListSegmentFavoritesQueryDto,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<ListSegmentFavoritesResponse> {
    return this.segments.listFavorites(user.userId, query);
  }
}
