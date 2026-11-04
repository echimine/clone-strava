import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
  UseGuards,
} from "@nestjs/common";
import { createZodDto, ZodResponse, ZodSerializerDto } from "nestjs-zod";
import {
  adminActivityDetailSchema,
  adminActivityListQuerySchema,
  adminActivityListResponseSchema,
  adminActivityRecomputeResponseSchema,
  adminActivityReprocessResponseSchema,
  adminActivityTextResponseSchema,
  type AdminActivityDetail,
  type AdminActivityListResponse,
  type AdminActivityRecomputeResponse,
  type AdminActivityReprocessResponse,
  type AdminActivityTextResponse,
  type AdminBatchResponse,
} from "@repo/contracts";
import { ActivitiesService, type ActivityLabel } from "@repo/core/activities";
import { AdminGuard } from "../../auth/admin.guard.js";
import { SessionGuard } from "../../auth/session.guard.js";
import { RequestId } from "../../common/request-id.decorator.js";
import { Audited, CurrentAuditDraft, type AuditDraft } from "../audit/audited.decorator.js";
import { AdminBatchResponseDto, batched } from "../failures/batched.js";
import { AdminReasonBodyDto } from "../sanctions/admin-reason-body.dto.js";
import { SanctionNotices, type SanctionNotice } from "../sanctions/sanction-notices.js";
import { AdminActivityAssembler } from "./admin-activity-assembler.js";

class AdminActivityListQueryDto extends createZodDto(adminActivityListQuerySchema) {}
class AdminActivityListResponseDto extends createZodDto(adminActivityListResponseSchema) {}
class AdminActivityDetailDto extends createZodDto(adminActivityDetailSchema) {}
class AdminActivityReprocessResponseDto extends createZodDto(adminActivityReprocessResponseSchema) {}
class AdminActivityTextResponseDto extends createZodDto(adminActivityTextResponseSchema) {}
class AdminActivityRecomputeResponseDto extends createZodDto(adminActivityRecomputeResponseSchema) {}

/**
 * `/v1/admin/activities/*` (ADR-038 §11, §17): the list, the detail, « Retraiter » and three
 * Sanctions on an Activity. Each action is the one endpoint every backoffice screen calls (the
 * moderation queue included, ADR-038 §1). Every Sanction names its author as the athlete
 * concerned and hands what the e-mail must name to {@link SanctionNotices}.
 */
@Controller("admin/activities")
@UseGuards(SessionGuard, AdminGuard)
export class AdminActivitiesController {
  constructor(
    private readonly activities: ActivitiesService,
    private readonly assembler: AdminActivityAssembler,
    private readonly notices: SanctionNotices,
  ) {}

  /** Every Activity, private ones included, newest created first. */
  @Get()
  @ZodResponse({ status: 200, type: AdminActivityListResponseDto })
  async list(@Query() query: AdminActivityListQueryDto): Promise<AdminActivityListResponse> {
    const { page, pageSize, ...filter } = query;
    const { rows, total } = await this.activities.listForAdmin(filter, { page, pageSize });
    return { items: await this.assembler.listItems(rows), total, page, pageSize };
  }

  /** Official values, status, public trace, Media, comments, kudos, import, efforts. */
  @Get(":id")
  @ZodResponse({ status: 200, type: AdminActivityDetailDto })
  detail(@Param("id", ParseUUIDPipe) id: string): Promise<AdminActivityDetail> {
    return this.assembler.detail(id);
  }

  /** « Retraiter » a `failed` Activity (`409 not_failed` otherwise). Not a Sanction. */
  @Post(":id/reprocess")
  @HttpCode(HttpStatus.ACCEPTED)
  @Audited("activity.reprocess", { reason: "none" })
  @ZodSerializerDto(AdminActivityReprocessResponseDto)
  async reprocess(
    @Param("id", ParseUUIDPipe) id: string,
    @RequestId() requestId: string | undefined,
    @CurrentAuditDraft() audit: AuditDraft,
  ): Promise<AdminActivityReprocessResponse> {
    const activity = await this.activities.reprocessFailed(id, requestId);
    audit.subjectUserId = activity.userId;
    return { id: activity.id, processingStatus: activity.processingStatus };
  }

  /**
   * « Recalculer » a processed Activity computed for another sport (`409 not_stale` otherwise):
   * `reprocess-activity` under a new job id (ADR-038 §14). Not a Sanction.
   */
  @Post(":id/recompute")
  @HttpCode(HttpStatus.ACCEPTED)
  @Audited("activity.recompute", { reason: "none" })
  @ZodSerializerDto(AdminActivityRecomputeResponseDto)
  async recompute(
    @Param("id", ParseUUIDPipe) id: string,
    @RequestId() requestId: string | undefined,
    @CurrentAuditDraft() audit: AuditDraft,
  ): Promise<AdminActivityRecomputeResponse> {
    const { userId, jobId } = await this.activities.recompute(id, requestId);
    audit.subjectUserId = userId;
    return { id, jobId };
  }

  /** « Retraiter les N en échec »: 500 failed Activities at most; one Journal entry. */
  @Post("reprocess-failed")
  @HttpCode(HttpStatus.ACCEPTED)
  @Audited("activity.reprocess.batch", { reason: "none", targetParam: null })
  @ZodSerializerDto(AdminBatchResponseDto)
  async reprocessFailed(
    @RequestId() requestId: string | undefined,
    @CurrentAuditDraft() audit: AuditDraft,
  ): Promise<AdminBatchResponse> {
    return batched(audit, await this.activities.reprocessAllFailed(requestId));
  }

  /** « Recalculer » every failed recomputation, 500 at most; one Journal entry. */
  @Post("recompute-stale")
  @HttpCode(HttpStatus.ACCEPTED)
  @Audited("activity.recompute.batch", { reason: "none", targetParam: null })
  @ZodSerializerDto(AdminBatchResponseDto)
  async recomputeStale(
    @RequestId() requestId: string | undefined,
    @CurrentAuditDraft() audit: AuditDraft,
  ): Promise<AdminBatchResponse> {
    return batched(audit, await this.activities.recomputeAllStale(requestId));
  }

  /** Sanction: deletes the Activity for good (`409 not_deletable` while processing). */
  @Delete(":id")
  @HttpCode(HttpStatus.NO_CONTENT)
  @Audited("activity.delete", { reason: "required" })
  async delete(
    @Param("id", ParseUUIDPipe) id: string,
    @Body() body: AdminReasonBodyDto,
    @CurrentAuditDraft() audit: AuditDraft,
  ): Promise<void> {
    const activity = await this.activities.deleteAsSanction(id);
    await this.sanctioned(audit, "activity.delete", body.reason, activity);
  }

  /** Sanction: removes one Media and its files (`404 media_not_found` if already gone). */
  @Delete(":id/media/:mediaId")
  @HttpCode(HttpStatus.NO_CONTENT)
  @Audited("media.remove", { reason: "required", targetParam: "mediaId" })
  async removeMedia(
    @Param("id", ParseUUIDPipe) id: string,
    @Param("mediaId", ParseUUIDPipe) mediaId: string,
    @Body() body: AdminReasonBodyDto,
    @CurrentAuditDraft() audit: AuditDraft,
  ): Promise<void> {
    const activity = await this.activities.removeMediaAsSanction(id, mediaId);
    await this.sanctioned(audit, "media.remove", body.reason, activity);
  }

  /** Sanction: the default title of the sport and start time, no description. */
  @Post(":id/reset-text")
  @HttpCode(HttpStatus.OK)
  @Audited("activity.text.reset", { reason: "required" })
  @ZodSerializerDto(AdminActivityTextResponseDto)
  async resetText(
    @Param("id", ParseUUIDPipe) id: string,
    @Body() body: AdminReasonBodyDto,
    @CurrentAuditDraft() audit: AuditDraft,
  ): Promise<AdminActivityTextResponse> {
    const reset = await this.activities.resetText(id);
    // The e-mail names the Activity as the athlete knew it.
    await this.sanctioned(audit, "activity.text.reset", body.reason, reset.previous);
    return { id: reset.previous.id, title: reset.title, description: reset.description };
  }

  private async sanctioned(
    audit: AuditDraft,
    action: SanctionNotice["action"],
    reason: string,
    activity: ActivityLabel,
  ): Promise<void> {
    audit.subjectUserId = activity.userId;
    await this.notices.send({
      auditEntryId: audit.entryId,
      action,
      athleteId: activity.userId,
      reason,
      activity: { title: activity.title, startedAt: activity.startedAt.toISOString() },
      comment: null,
    });
  }
}
