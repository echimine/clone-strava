import { Body, Controller, HttpCode, HttpStatus, Param, Post, UseGuards } from "@nestjs/common";
import { createZodDto, ZodSerializerDto } from "nestjs-zod";
import {
  completeActivityResponseSchema,
  createActivityRequestSchema,
  createActivityResponseSchema,
  renewUploadUrlResponseSchema,
  type ActivitySummary,
  type CompleteActivityResponse,
  type CreateActivityResponse,
  type RenewUploadUrlResponse,
} from "@repo/contracts";
import { ActivitiesService, type ActivityRecord } from "@repo/core/activities";
import { CurrentUser } from "../auth/current-user.decorator.js";
import { SessionGuard } from "../auth/session.guard.js";
import type { AuthenticatedUser } from "../auth/session.guard.js";

class CreateActivityRequestDto extends createZodDto(createActivityRequestSchema) {}
class CreateActivityResponseDto extends createZodDto(createActivityResponseSchema) {}
class RenewUploadUrlResponseDto extends createZodDto(renewUploadUrlResponseSchema) {}
class CompleteActivityResponseDto extends createZodDto(completeActivityResponseSchema) {}

/** `ActivityRecord` (core) -> `ActivitySummary` (contracts wire shape). */
function toActivitySummary(activity: ActivityRecord): ActivitySummary {
  return {
    id: activity.id,
    sportTypeCode: activity.sportTypeCode,
    visibility: activity.visibility,
    processingStatus: activity.processingStatus,
  };
}

/** `POST /v1/activities/*` (ADR-019 §1-4): activity creation flow. */
@Controller("activities")
@UseGuards(SessionGuard)
export class ActivitiesController {
  constructor(private readonly activitiesService: ActivitiesService) {}

  @Post()
  @ZodSerializerDto(CreateActivityResponseDto)
  async create(
    @Body() body: CreateActivityRequestDto,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<CreateActivityResponse> {
    // ADR-019 §1: 201 for a new id, 200 for a replayed call on the same
    // `pending` activity, 409 if the id belongs to another user, 422 on
    // invalid data -- all handled inside `CreateActivityUseCase`.
    const result = await this.activitiesService.create(user.userId, body);
    return { activity: toActivitySummary(result.activity), upload: result.uploadUrl };
  }

  @Post(":id/upload-url")
  @ZodSerializerDto(RenewUploadUrlResponseDto)
  renewUploadUrl(
    @Param("id") activityId: string,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<RenewUploadUrlResponse> {
    // ADR-019 §2: 409 if the activity is no longer `pending`.
    return this.activitiesService.requestUploadUrl(user.userId, activityId);
  }

  @Post(":id/complete")
  @HttpCode(HttpStatus.ACCEPTED)
  @ZodSerializerDto(CompleteActivityResponseDto)
  async complete(
    @Param("id") activityId: string,
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<CompleteActivityResponse> {
    // ADR-019 §4: HEAD the trace in the bucket (`trace_missing` /
    // `trace_too_large` -> 409), move to `processing`, enqueue
    // `process-activity`. Replayed calls on an already
    // `processing`/`processed` activity return 202 without enqueueing
    // again; `failed` returns 409 -- all handled by `CompleteActivityUseCase`.
    const activity = await this.activitiesService.complete(user.userId, activityId);
    return { activity: toActivitySummary(activity) };
  }
}
