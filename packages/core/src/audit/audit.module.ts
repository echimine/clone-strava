import { Module } from "@nestjs/common";
import { AuditService } from "./audit.service.js";
import { AdminAuditEntryRepository } from "./repositories/admin-audit-entry.repository.js";
import { RecordAuditEntryUseCase } from "./use-cases/record-audit-entry.use-case.js";

/**
 * `audit` module (ADR-038 §3, §18: layer 0, no dependency on another domain module). Exports
 * only its service.
 */
@Module({
  providers: [AdminAuditEntryRepository, RecordAuditEntryUseCase, AuditService],
  exports: [AuditService],
})
export class AuditModule {}
