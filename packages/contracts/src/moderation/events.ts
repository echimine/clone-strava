import type { ReportReason, ReportTargetType } from "./report.js";

/**
 * A Report opened a new case (ADR-038 §10), emitted by `moderation` after the commit, never for a
 * Report joining an open case. `apps/api` e-mails every Administrator on it.
 */
export const REPORT_CASE_OPENED_EVENT = "moderation.case.opened";

/** Ids and what the e-mail names: never a copy of the content (ADR-038 §10). */
export type ReportCaseOpenedEvent = { caseId: string; targetType: ReportTargetType; reason: ReportReason };
