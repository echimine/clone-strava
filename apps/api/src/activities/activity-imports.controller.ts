import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
  Res,
  UseGuards,
} from "@nestjs/common";
import type { Response } from "express";
import { createZodDto, ZodSerializerDto } from "nestjs-zod";
import {
  activityImportSchema,
  completeActivityImportResponseSchema,
  createActivityImportRequestSchema,
  createActivityImportResponseSchema,
  listActivityImportsQuerySchema,
  listActivityImportsResponseSchema,
  renewUploadUrlResponseSchema,
  type ActivityImport,
  type CompleteActivityImportResponse,
  type CreateActivityImportResponse,
  type ListActivityImportsResponse,
  type RenewUploadUrlResponse,
} from "@repo/contracts";
import { ActivitiesService } from "@repo/core/activities";
import { CurrentUser } from "../auth/current-user.decorator.js";
import { SessionGuard, type AuthenticatedUser } from "../auth/session.guard.js";
import { RequestId } from "../common/request-id.decorator.js";

class CreateActivityImportRequestDto extends createZodDto(createActivityImportRequestSchema) {}
class CreateActivityImportResponseDto extends createZodDto(createActivityImportResponseSchema) {}
class RenewUploadUrlResponseDto extends createZodDto(renewUploadUrlResponseSchema) {}
class CompleteActivityImportResponseDto extends createZodDto(completeActivityImportResponseSchema) {}
class ActivityImportDto extends createZodDto(activityImportSchema) {}
class ListActivityImportsQueryDto extends createZodDto(listActivityImportsQuerySchema) {}
class ListActivityImportsResponseDto extends createZodDto(listActivityImportsResponseSchema) {}

/** `/v1/activity-imports/*` (ADR-028 §3): import of a .gpx / .tcx / .fit file. */
@Controller("activity-imports")
@UseGuards(SessionGuard)
export class ActivityImportsController {
  constructor(private readonly activitiesService: ActivitiesService) {}

  @Post()
  @ZodSerializerDto(CreateActivityImportResponseDto)
  async create(
    @Body() body: CreateActivityImportRequestDto,
    @CurrentUser() user: AuthenticatedUser,
    @Res({ passthrough: true }) response: Response,
  ): Promise<CreateActivityImportResponse> {
    // `201` for a new id, `200` for a replayed call; `409` for another
    // user's id, `422` invalid data, `429` rate limit (ADR-028 §3, §9).
    const result = await this.activitiesService.createImport(user.userId, body);
    response.status(result.created ? HttpStatus.CREATED : HttpStatus.OK);
    return { import: result.import, upload: result.upload };
  }

  @Get()
  @ZodSerializerDto(ListActivityImportsResponseDto)
  list(
    @Query() query: ListActivityImportsQueryDto,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<ListActivityImportsResponse> {
    return this.activitiesService.listImports(user.userId, query);
  }

  @Get(":id")
  @ZodSerializerDto(ActivityImportDto)
  get(
    @Param("id", ParseUUIDPipe) importId: string,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<ActivityImport> {
    return this.activitiesService.getImport(user.userId, importId);
  }

  @Post(":id/upload-url")
  @HttpCode(HttpStatus.OK)
  @ZodSerializerDto(RenewUploadUrlResponseDto)
  renewUploadUrl(
    @Param("id", ParseUUIDPipe) importId: string,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<RenewUploadUrlResponse> {
    return this.activitiesService.requestImportUploadUrl(user.userId, importId);
  }

  @Post(":id/complete")
  @HttpCode(HttpStatus.ACCEPTED)
  @ZodSerializerDto(CompleteActivityImportResponseDto)
  async complete(
    @Param("id", ParseUUIDPipe) importId: string,
    @CurrentUser() user: AuthenticatedUser,
    @RequestId() requestId: string | undefined,
  ): Promise<CompleteActivityImportResponse> {
    // `HEAD` of the file (`file_missing` / `file_too_large` -> 409), then
    // `pending` -> `processing` and enqueue `import-activity`; replays are
    // `202` without a new job, `failed` is `409` (ADR-028 §3).
    return { import: await this.activitiesService.completeImport(user.userId, importId, requestId) };
  }
}
