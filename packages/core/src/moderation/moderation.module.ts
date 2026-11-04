import { Module } from "@nestjs/common";
import { ModerationService } from "./moderation.service.js";
import { ReportCaseRepository } from "./repositories/report-case.repository.js";
import { ReportRepository } from "./repositories/report.repository.js";
import { SubmitReportUseCase } from "./use-cases/submit-report.use-case.js";

/**
 * `moderation` module (ADR-038 §9, §18: layer 0, no dependency on another domain module).
 * Exports only its service.
 */
@Module({
  providers: [ReportCaseRepository, ReportRepository, SubmitReportUseCase, ModerationService],
  exports: [ModerationService],
})
export class ModerationModule {}
