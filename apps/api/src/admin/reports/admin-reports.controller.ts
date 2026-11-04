import {
  Body,
  ConflictException,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
  UseGuards,
} from "@nestjs/common";
import { createZodDto, ZodResponse } from "nestjs-zod";
import {
  ADMIN_REPORT_ERROR_CODES,
  adminReportCaseCloseBodySchema,
  adminReportCaseCloseResponseSchema,
  adminReportCaseDetailSchema,
  adminReportCaseListQuerySchema,
  adminReportCaseListResponseSchema,
  type AdminReportCaseCloseResponse,
  type AdminReportCaseDetail,
  type AdminReportCaseListResponse,
} from "@repo/contracts";
import { ModerationService, type ManualCaseOutcome, type ReportCaseRecord } from "@repo/core/moderation";
import { AdminGuard } from "../../auth/admin.guard.js";
import { CurrentUser } from "../../auth/current-user.decorator.js";
import { SessionGuard, type AuthenticatedUser } from "../../auth/session.guard.js";
import { Audited, CurrentAuditDraft, type AuditDraft } from "../audit/audited.decorator.js";
import { AdminReportAssembler } from "./admin-report-assembler.js";

class AdminReportCaseListQueryDto extends createZodDto(adminReportCaseListQuerySchema) {}
class AdminReportCaseListResponseDto extends createZodDto(adminReportCaseListResponseSchema) {}
class AdminReportCaseDetailDto extends createZodDto(adminReportCaseDetailSchema) {}
class AdminReportCaseCloseBodyDto extends createZodDto(adminReportCaseCloseBodySchema) {}
class AdminReportCaseCloseResponseDto extends createZodDto(adminReportCaseCloseResponseSchema) {}

/**
 * `/v1/admin/reports/*`, the moderation queue (ADR-038 §10, §17): one case per target, its
 * detail, and « Clore » as « Sanctionné » or « Rejeter ». The Sanctions themselves are the
 * endpoints of the Activities and users areas; a case closes by itself when its target disappears.
 * Closing is not a Sanction: its note is optional and recorded as the Journal entry's reason.
 */
@Controller("admin/reports")
@UseGuards(SessionGuard, AdminGuard)
export class AdminReportsController {
  constructor(
    private readonly moderation: ModerationService,
    private readonly assembler: AdminReportAssembler,
  ) {}

  /** « À traiter » or « Clos »; the oldest opened first, then the most reported. */
  @Get()
  @ZodResponse({ status: 200, type: AdminReportCaseListResponseDto })
  list(@Query() query: AdminReportCaseListQueryDto): Promise<AdminReportCaseListResponse> {
    return this.assembler.list(query);
  }

  /** The target now and the Reports' copies, the Reports, the author; `404 report_case_not_found`. */
  @Get(":caseId")
  @ZodResponse({ status: 200, type: AdminReportCaseDetailDto })
  detail(@Param("caseId", ParseUUIDPipe) caseId: string): Promise<AdminReportCaseDetail> {
    return this.assembler.detail(caseId);
  }

  /**
   * « Sanctionné »: `409 no_sanction` without a Sanction in the Journal since the opening, on the
   * target or its author; `409 case_closed` when already closed.
   */
  @Post(":caseId/resolve")
  @HttpCode(HttpStatus.OK)
  @Audited("report.resolve", { reason: "optional", targetParam: "caseId" })
  @ZodResponse({ status: 200, type: AdminReportCaseCloseResponseDto })
  async resolve(
    @Param("caseId", ParseUUIDPipe) caseId: string,
    @Body() body: AdminReportCaseCloseBodyDto,
    @CurrentUser() administrator: AuthenticatedUser,
    @CurrentAuditDraft() audit: AuditDraft,
  ): Promise<AdminReportCaseCloseResponse> {
    const { reportCase } = await this.assembler.getCase(caseId);
    if (reportCase.status === "open" && !(await this.assembler.canResolve(reportCase))) {
      throw new ConflictException({
        code: ADMIN_REPORT_ERROR_CODES.noSanction,
        message: "No Sanction recorded since the case opened",
      });
    }
    return this.close(reportCase, "actioned", body, administrator, audit);
  }

  /** « Rejeter »: `409 case_closed` when already closed. */
  @Post(":caseId/dismiss")
  @HttpCode(HttpStatus.OK)
  @Audited("report.dismiss", { reason: "optional", targetParam: "caseId" })
  @ZodResponse({ status: 200, type: AdminReportCaseCloseResponseDto })
  async dismiss(
    @Param("caseId", ParseUUIDPipe) caseId: string,
    @Body() body: AdminReportCaseCloseBodyDto,
    @CurrentUser() administrator: AuthenticatedUser,
    @CurrentAuditDraft() audit: AuditDraft,
  ): Promise<AdminReportCaseCloseResponse> {
    const { reportCase } = await this.assembler.getCase(caseId);
    return this.close(reportCase, "dismissed", body, administrator, audit);
  }

  /** Closes the case; the Journal entry names the target's author, the count, and the note as its reason. */
  private async close(
    reportCase: ReportCaseRecord,
    outcome: ManualCaseOutcome,
    body: AdminReportCaseCloseBodyDto,
    administrator: AuthenticatedUser,
    audit: AuditDraft,
  ): Promise<AdminReportCaseCloseResponse> {
    const note = body.note ?? null;
    const closed = await this.moderation.close(reportCase.id, outcome, administrator.userId, note);
    audit.subjectUserId = reportCase.targetUserId;
    audit.details = { count: closed.count };
    audit.reason = note;
    return { id: closed.id, status: closed.status, closedAt: closed.closedAt.toISOString(), count: closed.count };
  }
}
