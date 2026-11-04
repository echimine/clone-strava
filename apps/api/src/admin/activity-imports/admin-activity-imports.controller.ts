import { Controller, HttpCode, HttpStatus, Param, ParseUUIDPipe, Post, UseGuards } from "@nestjs/common";
import { createZodDto, ZodSerializerDto } from "nestjs-zod";
import { activityImportSchema, type ActivityImport, type AdminBatchResponse } from "@repo/contracts";
import { ActivitiesService } from "@repo/core/activities";
import { AdminGuard } from "../../auth/admin.guard.js";
import { SessionGuard } from "../../auth/session.guard.js";
import { RequestId } from "../../common/request-id.decorator.js";
import { Audited, CurrentAuditDraft, type AuditDraft } from "../audit/audited.decorator.js";
import { AdminBatchResponseDto, batched } from "../failures/batched.js";

class ActivityImportDto extends createZodDto(activityImportSchema) {}

/** `/v1/admin/activity-imports/*` (ADR-028 §7, ADR-038 §14, §17). */
@Controller("admin/activity-imports")
@UseGuards(SessionGuard, AdminGuard)
export class AdminActivityImportsController {
  constructor(private readonly activitiesService: ActivitiesService) {}

  /** « Retraiter les N en échec » (ADR-038 §14): 500 failed imports at most; one Journal entry. */
  @Post("reprocess-failed")
  @HttpCode(HttpStatus.ACCEPTED)
  @Audited("import.reprocess.batch", { reason: "none", targetParam: null })
  @ZodSerializerDto(AdminBatchResponseDto)
  async reprocessFailed(
    @RequestId() requestId: string | undefined,
    @CurrentAuditDraft() audit: AuditDraft,
  ): Promise<AdminBatchResponse> {
    return batched(audit, await this.activitiesService.reprocessAllFailedImports(requestId));
  }

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
