import { Injectable } from "@nestjs/common";
import { toOffsetPage } from "../infrastructure/index.js";
import type { NewReport, ReportedItems, ReportOutcome } from "./domain/report.js";
import type {
  CaseReportRecord,
  ClosedCase,
  ManualCaseOutcome,
  ReportCaseFilter,
  ReportCaseRecord,
  ReportCaseRow,
} from "./domain/report-case.js";
import { ReportCaseRepository } from "./repositories/report-case.repository.js";
import { ReportRepository, type UserReportRow } from "./repositories/report.repository.js";

export type { UserReportRow } from "./repositories/report.repository.js";
import { CloseReportCaseUseCase } from "./use-cases/close-report-case.use-case.js";
import { SubmitReportUseCase } from "./use-cases/submit-report.use-case.js";

/**
 * Public facade of the `moderation` module (ADR-038 §9, §10, §18: layer 0, owns
 * `moderation.report_case` and `moderation.report`). It never reads another module: `apps/api`
 * reads a Report's target (existence, visibility, author, texts) and hands it over, and reads the
 * Journal before a case closes as « Sanctionné ». Cases close by themselves when their target
 * disappears (`TargetDeletionListener`).
 */
@Injectable()
export class ModerationService {
  constructor(
    private readonly submitReport: SubmitReportUseCase,
    private readonly closeCase: CloseReportCaseUseCase,
    private readonly reports: ReportRepository,
    private readonly cases: ReportCaseRepository,
  ) {}

  /**
   * Records a Report: opens the target's case or joins the open one. `422 note_required` /
   * `reason_not_allowed`; `429 report_limit_reached` past 20 per 24 h; `already_reported` when
   * this athlete has a Report in the open case. Emits `moderation.case.opened` after the commit
   * when it opened a case.
   */
  report(input: NewReport): Promise<ReportOutcome> {
    return this.submitReport.execute(input);
  }

  /**
   * The user sheet's « Signalements » tabs (ADR-038 §5): Reports on `userId` or their content,
   * and Reports `userId` made, newest first, at most `limit` each.
   */
  async getReportsOfUser(userId: string, limit: number): Promise<{ received: UserReportRow[]; sent: UserReportRow[] }> {
    const [received, sent] = await Promise.all([
      this.reports.findReceivedBy(userId, limit),
      this.reports.findSentBy(userId, limit),
    ]);
    return { received, sent };
  }

  /** The viewer filter's `moderation` source (ADR-038 §7): what `reporterId` ever reported. */
  async getReportedItems(reporterId: string): Promise<ReportedItems> {
    const rows = await this.reports.findReportedTargets(reporterId, ["activity", "comment"]);
    return {
      activityIds: rows.filter((row) => row.targetType === "activity").map((row) => row.targetId),
      commentIds: rows.filter((row) => row.targetType === "comment").map((row) => row.targetId),
    };
  }

  // --- Moderation queue (ADR-038 §10) ---

  /** One page of the queue: open (« À traiter ») or closed (« Clos ») cases. */
  async listCases(
    filter: ReportCaseFilter,
    page: { page: number; pageSize: number },
  ): Promise<{ items: ReportCaseRow[]; total: number; page: number; pageSize: number }> {
    const { rows, total } = await this.cases.findPage(filter, page);
    return toOffsetPage(rows, total, page);
  }

  /** A case and its Reports (oldest first); undefined when unknown. */
  async getCase(caseId: string): Promise<{ reportCase: ReportCaseRecord; reports: CaseReportRecord[] } | undefined> {
    const reportCase = await this.cases.findById(caseId);
    if (!reportCase) {
      return undefined;
    }
    return { reportCase, reports: await this.reports.findByCase(caseId) };
  }

  /**
   * « Clore »: « Sanctionné » or « Rejeter », with an optional note; the copies are erased.
   * `404 report_case_not_found`, `409 case_closed`. The caller checks the Journal first for
   * « Sanctionné ».
   */
  close(caseId: string, outcome: ManualCaseOutcome, closedBy: string, note: string | null): Promise<ClosedCase> {
    return this.closeCase.execute(caseId, outcome, closedBy, note);
  }

  /** Reports on `userId` or their content (a case author's « Signalements reçus »). */
  countReportsReceived(userId: string): Promise<number> {
    return this.reports.countReceivedBy(userId);
  }

  /** Open cases and the oldest opening (dashboard, ADR-038 §15). */
  countOpenCases(): Promise<{ count: number; oldestOpenedAt: Date | null }> {
    return this.cases.countOpen();
  }

  /** Batch read: the ids among `caseIds` of cases that exist (Journal links). */
  getExistingCaseIds(caseIds: string[]): Promise<Set<string>> {
    return this.cases.findExistingIds(caseIds);
  }
}
