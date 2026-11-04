import { Injectable } from "@nestjs/common";
import type { NewReport, ReportedItems, ReportOutcome } from "./domain/report.js";
import { ReportRepository, type UserReportRow } from "./repositories/report.repository.js";

export type { UserReportRow } from "./repositories/report.repository.js";
import { SubmitReportUseCase } from "./use-cases/submit-report.use-case.js";

/**
 * Public facade of the `moderation` module (ADR-038 §9, §10, §18: layer 0, owns
 * `moderation.report_case` and `moderation.report`). It never reads another module: `apps/api`
 * reads a Report's target (existence, visibility, author, texts) and hands it over.
 */
@Injectable()
export class ModerationService {
  constructor(
    private readonly submitReport: SubmitReportUseCase,
    private readonly reports: ReportRepository,
  ) {}

  /**
   * Records a Report: opens the target's case or joins the open one. `422 note_required` /
   * `reason_not_allowed`; `429 report_limit_reached` past 20 per 24 h; `already_reported` when
   * this athlete has a Report in the open case.
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

  /**
   * Account deletion (ADR-038 §13): the Reports `reporterId` sent stay, their cases still to
   * review, but without their note. Called just before the account goes; the foreign key then
   * sets `reporter_id` to null. Returns how many notes were erased.
   */
  eraseNotesOfReporter(reporterId: string): Promise<number> {
    return this.reports.clearNotesOf(reporterId);
  }

  /** The viewer filter's `moderation` source (ADR-038 §7): what `reporterId` ever reported. */
  async getReportedItems(reporterId: string): Promise<ReportedItems> {
    const rows = await this.reports.findReportedTargets(reporterId, ["activity", "comment"]);
    return {
      activityIds: rows.filter((row) => row.targetType === "activity").map((row) => row.targetId),
      commentIds: rows.filter((row) => row.targetType === "comment").map((row) => row.targetId),
    };
  }
}
