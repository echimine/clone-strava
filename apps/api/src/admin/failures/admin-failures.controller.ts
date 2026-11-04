import { Controller, Get, Query, UseGuards } from "@nestjs/common";
import { createZodDto, ZodResponse } from "nestjs-zod";
import {
  adminFailedActivityListResponseSchema,
  adminFailedImportListResponseSchema,
  adminFailureListQuerySchema,
  adminStaleActivityListResponseSchema,
  type AdminFailedActivityListResponse,
  type AdminFailedImportListResponse,
  type AdminStaleActivityListResponse,
} from "@repo/contracts";
import { AdminGuard } from "../../auth/admin.guard.js";
import { SessionGuard } from "../../auth/session.guard.js";
import { AdminFailureAssembler } from "./admin-failure-assembler.js";

class AdminFailureListQueryDto extends createZodDto(adminFailureListQuerySchema) {}
class AdminFailedActivityListResponseDto extends createZodDto(adminFailedActivityListResponseSchema) {}
class AdminFailedImportListResponseDto extends createZodDto(adminFailedImportListResponseSchema) {}
class AdminStaleActivityListResponseDto extends createZodDto(adminStaleActivityListResponseSchema) {}

/**
 * `/v1/admin/failures/*` (ADR-038 §14): the three lists of the Jobs screen's "Échecs" tab. Their
 * relaunches are the domain actions of each area: `POST /v1/admin/activities/:id/reprocess`,
 * `…/:id/recompute`, `/v1/admin/activity-imports/:id/reprocess`, and their batches.
 */
@Controller("admin/failures")
@UseGuards(SessionGuard, AdminGuard)
export class AdminFailuresController {
  constructor(private readonly assembler: AdminFailureAssembler) {}

  /** `failed` Activities, newest first. */
  @Get("activities")
  @ZodResponse({ status: 200, type: AdminFailedActivityListResponseDto })
  activities(@Query() query: AdminFailureListQueryDto): Promise<AdminFailedActivityListResponse> {
    return this.assembler.activitiesPage(query);
  }

  /** `failed` imports, newest first. */
  @Get("imports")
  @ZodResponse({ status: 200, type: AdminFailedImportListResponseDto })
  imports(@Query() query: AdminFailureListQueryDto): Promise<AdminFailedImportListResponse> {
    return this.assembler.importsPage(query);
  }

  /** Failed recomputations: processed Activities computed for another sport, newest edit first. */
  @Get("recomputes")
  @ZodResponse({ status: 200, type: AdminStaleActivityListResponseDto })
  recomputes(@Query() query: AdminFailureListQueryDto): Promise<AdminStaleActivityListResponse> {
    return this.assembler.recomputesPage(query);
  }
}
