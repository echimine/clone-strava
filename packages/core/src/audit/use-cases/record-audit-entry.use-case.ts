import { Injectable } from "@nestjs/common";
import { AUDIT_ACTION_TARGETS } from "@repo/contracts";
import type { NewAuditEntry } from "../domain/audit-entry.js";
import { AdminAuditEntryRepository } from "../repositories/admin-audit-entry.repository.js";

/**
 * Appends one entry to the Journal (ADR-038 §3). The target type defaults to the action's own;
 * an empty reason is stored as none. Returns the entry's id.
 */
@Injectable()
export class RecordAuditEntryUseCase {
  constructor(private readonly entries: AdminAuditEntryRepository) {}

  execute(entry: NewAuditEntry): Promise<string> {
    return this.entries.insert({
      ...(entry.id ? { id: entry.id } : {}),
      actorId: entry.actorId,
      action: entry.action,
      targetType: entry.targetType ?? AUDIT_ACTION_TARGETS[entry.action],
      targetId: entry.targetId,
      subjectUserId: entry.subjectUserId ?? null,
      reason: entry.reason?.trim() || null,
      details: entry.details && Object.keys(entry.details).length > 0 ? entry.details : null,
      requestId: entry.requestId ?? null,
    });
  }
}
