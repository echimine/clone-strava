import { Body, Controller, HttpStatus, Post, Res, UseGuards } from "@nestjs/common";
import { ApiResponse } from "@nestjs/swagger";
import type { Response } from "express";
import { createZodDto, ZodResponse } from "nestjs-zod";
import {
  createReportRequestSchema,
  createReportResponseSchema,
  type CreateReportResponse,
} from "@repo/contracts";
import { ModerationService } from "@repo/core/moderation";
import { CurrentUser } from "../auth/current-user.decorator.js";
import { SessionGuard, type AuthenticatedUser } from "../auth/session.guard.js";
import { ViewerFilter } from "../viewer-filter/viewer-filter.js";
import { ReportTargetReader } from "./report-target-reader.js";

class CreateReportRequestDto extends createZodDto(createReportRequestSchema) {}
class CreateReportResponseDto extends createZodDto(createReportResponseSchema) {}

/**
 * Reports from the app (ADR-038 §9): the target is read through its module, then handed to
 * `moderation`. A reported comment or Activity disappears for the reporter for good, through the
 * viewer filter; a reported athlete is never hidden by the Report itself.
 */
@Controller("reports")
@UseGuards(SessionGuard)
export class ReportsController {
  constructor(
    private readonly moderation: ModerationService,
    private readonly targets: ReportTargetReader,
    private readonly viewerFilter: ViewerFilter,
  ) {}

  /**
   * `201` a new Report; `200` the athlete already has a Report in the target's open case ("Déjà
   * signalé", nothing written). `404` target missing or not visible; `422` own content
   * (`cannot_report_own_content`), `note_required` with « other », `reason_not_allowed`
   * (impersonation of something else than an athlete); `429 report_limit_reached` past 20 per
   * 24 h, with `Retry-After`.
   */
  @Post()
  @ZodResponse({ status: 201, type: CreateReportResponseDto, description: "Reported" })
  @ApiResponse({ status: 200, type: CreateReportResponseDto.Output, description: "Already reported" })
  async create(
    @Body() body: CreateReportRequestDto,
    @CurrentUser() user: AuthenticatedUser,
    @Res({ passthrough: true }) response: Response,
  ): Promise<CreateReportResponse> {
    const filter = await this.viewerFilter.for(user.userId);
    const target = await this.targets.read(user.userId, body.targetType, body.targetId, filter);
    const outcome = await this.moderation.report({
      reporterId: user.userId,
      targetType: body.targetType,
      targetId: body.targetId,
      targetUserId: target.authorId,
      reason: body.reason,
      note: body.note,
      snapshot: target.snapshot,
    });
    response.status(outcome.kind === "created" ? HttpStatus.CREATED : HttpStatus.OK);
    return { id: outcome.reportId };
  }
}
