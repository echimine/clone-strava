import {
  Body,
  Controller,
  Delete,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Post,
  Res,
  UseGuards,
} from "@nestjs/common";
import { ApiResponse } from "@nestjs/swagger";
import type { Response } from "express";
import { createZodDto, ZodResponse } from "nestjs-zod";
import {
  confirmMediaRequestSchema,
  confirmMediaResponseSchema,
  mediaUploadUrlsRequestSchema,
  mediaUploadUrlsResponseSchema,
  type ConfirmMediaResponse,
  type MediaUploadUrlsResponse,
} from "@repo/contracts";
import { ActivitiesService } from "@repo/core/activities";
import { CurrentUser } from "../auth/current-user.decorator.js";
import { SessionGuard, type AuthenticatedUser } from "../auth/session.guard.js";
import { MediaAssembler } from "../media/media-assembler.js";

class MediaUploadUrlsRequestDto extends createZodDto(mediaUploadUrlsRequestSchema) {}
class MediaUploadUrlsResponseDto extends createZodDto(mediaUploadUrlsResponseSchema) {}
class ConfirmMediaRequestDto extends createZodDto(confirmMediaRequestSchema) {}
class ConfirmMediaResponseDto extends createZodDto(confirmMediaResponseSchema) {}

/**
 * `/v1/activities/:id/media` (ADR-037 §4): the iPhone sends a Media's files straight to the
 * bucket, then has the API confirm it. Author only, whatever the Activity's processing state:
 * `404 activity_not_found` when the viewer cannot see it, `403 not_activity_author` otherwise.
 */
@Controller("activities/:id/media")
@UseGuards(SessionGuard)
export class ActivityMediaController {
  constructor(
    private readonly activities: ActivitiesService,
    private readonly assembler: MediaAssembler,
  ) {}

  /**
   * A 24-hour pre-signed `PUT` per file, sent with `Content-Type` and `Content-Length` exactly as
   * requested (both signed). Writes nothing: replay it to renew a URL after a `403` from the
   * bucket. `422 validation_error` for a file set other than the kind's (ADR-037 §3) or a file
   * above its size; `409 media_limit_reached` with 8 confirmed Media.
   */
  @Post("upload-urls")
  @HttpCode(HttpStatus.OK)
  @ZodResponse({ status: 200, type: MediaUploadUrlsResponseDto })
  requestUploadUrls(
    @Param("id", ParseUUIDPipe) activityId: string,
    @Body() body: MediaUploadUrlsRequestDto,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<MediaUploadUrlsResponse> {
    return this.activities.requestMediaUploadUrls(user.userId, activityId, body);
  }

  /**
   * Confirms a Media whose files were all sent: `201` with the Media as every read gives it, `200`
   * with the same Media on a replay of the same `id`. `409 media_missing` when a file is not in the
   * bucket (send it again), `409 media_invalid` when one is too large or not a JPEG / MP4, `409
   * media_limit_reached` with 8 confirmed Media, `409 media_id_taken` for an id of another Activity.
   */
  @Post()
  @ZodResponse({ status: 201, type: ConfirmMediaResponseDto, description: "Confirmed" })
  @ApiResponse({ status: 200, type: ConfirmMediaResponseDto.Output, description: "Replayed" })
  async confirm(
    @Param("id", ParseUUIDPipe) activityId: string,
    @Body() body: ConfirmMediaRequestDto,
    @CurrentUser() user: AuthenticatedUser,
    @Res({ passthrough: true }) response: Response,
  ): Promise<ConfirmMediaResponse> {
    const result = await this.activities.confirmMedia(user.userId, activityId, body);
    response.status(result.created ? HttpStatus.CREATED : HttpStatus.OK);
    return { media: await this.assembler.sign(result.media) };
  }

  /**
   * Deletes the Media and its files: `204`, also when it is already gone. The map comes first
   * again if that Media was first.
   */
  @Delete(":mediaId")
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiResponse({ status: 204, description: "Deleted" })
  async remove(
    @Param("id", ParseUUIDPipe) activityId: string,
    @Param("mediaId", ParseUUIDPipe) mediaId: string,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<void> {
    await this.activities.deleteMedia(user.userId, activityId, mediaId);
  }
}
