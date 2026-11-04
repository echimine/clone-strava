import { Controller, HttpCode, HttpStatus, Param, ParseUUIDPipe, Post, UseGuards } from "@nestjs/common";
import { createZodDto, ZodSerializerDto } from "nestjs-zod";
import { activityImportSchema, type ActivityImport } from "@repo/contracts";
import { ActivitiesService } from "@repo/core/activities";
import { AdminGuard } from "../../auth/admin.guard.js";
import { SessionGuard } from "../../auth/session.guard.js";
import { RequestId } from "../../common/request-id.decorator.js";
import { Audited } from "../audit/audited.decorator.js";

class ActivityImportDto extends createZodDto(activityImportSchema) {}

/** `/v1/admin/activity-imports/*` (ADR-028 §7, ADR-038 §17). */
@Controller("admin/activity-imports")
@UseGuards(SessionGuard, AdminGuard)
export class AdminActivityImportsController {
  constructor(private readonly activitiesService: ActivitiesService) {}

  /** ADR-028 §7: a failed import goes back to `processing` and is re-enqueued. Not a Sanction. */
  @Post(":id/reprocess")
  @HttpCode(HttpStatus.ACCEPTED)
  @Audited("import.reprocess", { reason: "none" })
  @ZodSerializerDto(ActivityImportDto)
  reprocessImport(
    @Param("id", ParseUUIDPipe) importId: string,
    @RequestId() requestId: string | undefined,
  ): Promise<ActivityImport> {
    return this.activitiesService.reprocessImport(importId, requestId);
  }
}
