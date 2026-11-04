import { Module } from "@nestjs/common";
import { TargetDeletionListener } from "./listeners/target-deletion.listener.js";
import { ModerationService } from "./moderation.service.js";
import { ReportCaseRepository } from "./repositories/report-case.repository.js";
import { ReportRepository } from "./repositories/report.repository.js";
import { CloseCasesOfGoneTargetUseCase } from "./use-cases/close-cases-of-gone-target.use-case.js";
import { CloseReportCaseUseCase } from "./use-cases/close-report-case.use-case.js";
import { SubmitReportUseCase } from "./use-cases/submit-report.use-case.js";

/**
 * `moderation` module (ADR-038 §9, §10, §18: layer 0, no dependency on another domain module).
 * Exports only its service; listens to the deletion events of comments, Activities and accounts.
 */
@Module({
  providers: [
    ReportCaseRepository,
    ReportRepository,
    SubmitReportUseCase,
    CloseReportCaseUseCase,
    CloseCasesOfGoneTargetUseCase,
    TargetDeletionListener,
    ModerationService,
  ],
  exports: [ModerationService],
})
export class ModerationModule {}
