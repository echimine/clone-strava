import type { ReportCaseStatus, ReportReason, ReportTargetType } from "@repo/contracts";

/** A case as stored (ADR-038 §10, §18). */
export interface ReportCaseRecord {
  id: string;
  targetType: ReportTargetType;
  targetId: string;
  /** The target's author (the athlete themself for an athlete); null for a Segment with no creator (ADR-039 §11). */
  targetUserId: string | null;
  status: ReportCaseStatus;
  openedAt: Date;
  closedAt: Date | null;
  /** The Administrator who closed it; null for « Système » (or while open). */
  closedBy: string | null;
  closeNote: string | null;
}

/** A row of the moderation queue: the case, its Reports counted, and the first Report's copy. */
export interface ReportCaseRow extends ReportCaseRecord {
  reportCount: number;
  /** Distinct reasons, in the order of the reason list. */
  reasons: ReportReason[];
  /** The first Report's copy; null once the case is closed. */
  firstSnapshot: Record<string, unknown> | null;
}

/** A Report of a case, oldest first in its detail. */
export interface CaseReportRecord {
  id: string;
  /** Null once the reporter's account is deleted. */
  reporterId: string | null;
  reason: ReportReason;
  note: string | null;
  createdAt: Date;
  /** Null once the case is closed or the author's account deleted. */
  snapshot: Record<string, unknown> | null;
}

/** Filters and sort of the queue (`GET /v1/admin/reports`); `from`/`to` are Paris days of the opening. */
export interface ReportCaseFilter {
  state: "open" | "closed";
  targetType?: ReportTargetType;
  reason?: ReportReason;
  from?: string;
  to?: string;
  sort: "openedAt" | "reportCount" | "closedAt";
  order: "asc" | "desc";
}

/** How an Administrator closes a case: « Sanctionné » or « Rejeter » (ADR-038 §10). */
export type ManualCaseOutcome = "actioned" | "dismissed";

export interface ClosedCase {
  id: string;
  status: ReportCaseStatus;
  closedAt: Date;
  /** Reports closed with the case. */
  count: number;
}

/** Outcome of a case whose target disappeared: « Sanctionné » after a Sanction, else « Cible supprimée ». */
export function goneTargetOutcome(bySanction: boolean): Extract<ReportCaseStatus, "actioned" | "target_gone"> {
  return bySanction ? "actioned" : "target_gone";
}
