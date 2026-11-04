import { Injectable } from "@nestjs/common";
import { toOffsetPage } from "../infrastructure/index.js";
import type { AuditEntryFilter, AuditEntryPage, NewAuditEntry } from "./domain/audit-entry.js";
import { AdminAuditEntryRepository } from "./repositories/admin-audit-entry.repository.js";
import { RecordAuditEntryUseCase } from "./use-cases/record-audit-entry.use-case.js";

/**
 * Public facade of the `audit` module (ADR-038 §3: layer 0, owns `audit.admin_audit_entry`).
 * Admin routes write through `@Audited` in `apps/api`; jobs and hooks call `record` directly
 * (author null for "Système").
 */
@Injectable()
export class AuditService {
  constructor(
    private readonly recordUseCase: RecordAuditEntryUseCase,
    private readonly entries: AdminAuditEntryRepository,
  ) {}

  /** Appends an entry and returns its id. */
  record(entry: NewAuditEntry): Promise<string> {
    return this.recordUseCase.execute(entry);
  }

  /** A page of the Journal, newest first. */
  async list(filter: AuditEntryFilter, page: { page: number; pageSize: number }): Promise<AuditEntryPage> {
    const { rows, total } = await this.entries.findPage(filter, page);
    return toOffsetPage(rows, total, page);
  }

  /** Everyone who authored an entry, for the author filter. */
  listActorIds(): Promise<string[]> {
    return this.entries.findActorIds();
  }
}
