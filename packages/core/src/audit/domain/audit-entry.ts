import type { AuditAction, AuditTargetType } from "@repo/contracts";

/** One stored entry of the Journal (ADR-038 §3), ids only. */
export interface AuditEntryRecord {
  id: string;
  createdAt: Date;
  /** The Administrator; null for "Système". */
  actorId: string | null;
  action: AuditAction;
  targetType: AuditTargetType;
  targetId: string | null;
  subjectUserId: string | null;
  reason: string | null;
  details: Record<string, unknown> | null;
  requestId: string | null;
}

/**
 * An entry to write. `targetType` defaults to the action's own (`AUDIT_ACTION_TARGETS`); `id`
 * lets the caller pick the id beforehand, e.g. to key an e-mail job on it (ADR-038 §4).
 */
export interface NewAuditEntry {
  id?: string;
  actorId: string | null;
  action: AuditAction;
  targetType?: AuditTargetType;
  targetId: string | null;
  subjectUserId?: string | null;
  reason?: string | null;
  details?: Record<string, unknown> | null;
  requestId?: string | null;
}

/** Filters of the Journal; `from`/`to` are Paris days, both included. */
export interface AuditEntryFilter {
  actorId?: string;
  action?: AuditAction;
  subjectUserId?: string;
  from?: string;
  to?: string;
}

export interface AuditEntryPage {
  items: AuditEntryRecord[];
  total: number;
  page: number;
  pageSize: number;
}
