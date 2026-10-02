import { Controller, Get, HttpCode, HttpStatus, Param, ParseUUIDPipe, Post, UseGuards } from "@nestjs/common";
import { createZodDto, ZodSerializerDto } from "nestjs-zod";
import { activityImportSchema, type ActivityImport } from "@repo/contracts";
import { ActivitiesService } from "@repo/core/activities";
import { AdminGuard } from "../auth/admin.guard.js";
import { SessionGuard } from "../auth/session.guard.js";
import { RequestId } from "../common/request-id.decorator.js";

class ActivityImportDto extends createZodDto(activityImportSchema) {}

/**
 * `/v1/admin/*` (ADR-021 §1 "Not a module: admin"): admin endpoints live
 * here and call the services of the relevant domain modules directly,
 * e.g. `POST /v1/admin/activities/:id/reprocess` ->
 * `ActivitiesService.reprocess(id)` (ADR-019 §6).
 */
@Controller("admin")
@UseGuards(SessionGuard, AdminGuard)
export class AdminController {
  constructor(private readonly activitiesService: ActivitiesService) {}

  @Get()
  ping(): { status: "ok" } {
    return { status: "ok" };
  }

  /** ADR-028 §7: a failed import goes back to `processing` and is re-enqueued. */
  @Post("activity-imports/:id/reprocess")
  @HttpCode(HttpStatus.ACCEPTED)
  @ZodSerializerDto(ActivityImportDto)
  reprocessImport(
    @Param("id", ParseUUIDPipe) importId: string,
    @RequestId() requestId: string | undefined,
  ): Promise<ActivityImport> {
    return this.activitiesService.reprocessImport(importId, requestId);
  }
}
