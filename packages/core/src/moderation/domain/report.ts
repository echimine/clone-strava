import type { ReportReason, ReportSnapshot, ReportTargetType } from "@repo/contracts";

/** A Report as `apps/api` hands it over, once it has read the target through its module. */
export interface NewReport {
  reporterId: string;
  targetType: ReportTargetType;
  targetId: string;
  /** The target's author (the athlete themself for an `athlete` target); null for a Segment with no creator (ADR-039 §11). */
  targetUserId: string | null;
  reason: ReportReason;
  note?: string | null;
  /** Copy of the target's texts (ADR-038 §9), shaped by `targetType`. */
  snapshot: ReportSnapshot;
}

/**
 * `created`: a new Report, and `caseOpened` when it opened the target's case (the moment #213
 * e-mails the Administrators). `already_reported`: this athlete already has a Report in the open
 * case ("Déjà signalé"), nothing written.
 */
export type ReportOutcome =
  | { kind: "created"; reportId: string; caseId: string; caseOpened: boolean }
  | { kind: "already_reported"; reportId: string; caseId: string };

/** Items a reporter reported (ADR-038 §9), hidden from them for good whatever the outcome. */
export interface ReportedItems {
  activityIds: string[];
  commentIds: string[];
}

export type ReportRuleViolation = "note_required" | "reason_not_allowed";

/**
 * The rules spanning fields of a Report (ADR-038 §9): "Usurpation d'identité" is for an athlete
 * only; "Autre" needs a note. The note is trimmed, and an empty one is no note.
 */
export function checkReport(
  targetType: ReportTargetType,
  reason: ReportReason,
  note: string | null | undefined,
): { note: string | null } | { violation: ReportRuleViolation } {
  const trimmed = note?.trim() ?? "";
  if (reason === "impersonation" && targetType !== "athlete") {
    return { violation: "reason_not_allowed" };
  }
  if (reason === "other" && trimmed === "") {
    return { violation: "note_required" };
  }
  return { note: trimmed === "" ? null : trimmed };
}
