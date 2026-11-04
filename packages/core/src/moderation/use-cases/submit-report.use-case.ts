import { HttpException, HttpStatus, Inject, Injectable, UnprocessableEntityException } from "@nestjs/common";
import { ANALYTICS_EVENTS, REPORT_LIMIT_PER_DAY } from "@repo/contracts";
import type { Database } from "@repo/db";
import { AnalyticsService } from "../../analytics/index.js";
import { DATABASE } from "../../infrastructure/index.js";
import { checkReport, type NewReport, type ReportOutcome } from "../domain/report.js";
import { ReportCaseRepository } from "../repositories/report-case.repository.js";
import { ReportRepository } from "../repositories/report.repository.js";

const WINDOW_HOURS = 24;

/**
 * `POST /v1/reports` once `apps/api` has read the target (ADR-038 §9, §10): the first Report of
 * a target opens its case, the next ones join it. A repeat by the same athlete on the open case
 * writes nothing ("Déjà signalé"). At most 20 Reports per sliding 24 h per athlete (`429
 * report_limit_reached`, with `Retry-After`). `report_submitted` goes to PostHog after commit,
 * never on a repeat.
 */
@Injectable()
export class SubmitReportUseCase {
  constructor(
    @Inject(DATABASE) private readonly db: Database,
    private readonly cases: ReportCaseRepository,
    private readonly reports: ReportRepository,
    private readonly analytics: AnalyticsService,
  ) {}

  async execute(input: NewReport): Promise<ReportOutcome> {
    const checked = checkReport(input.targetType, input.reason, input.note);
    if ("violation" in checked) {
      throw new UnprocessableEntityException({
        code: checked.violation,
        message:
          checked.violation === "note_required"
            ? "A note is required with the reason « other »"
            : "This reason does not apply to this target",
      });
    }

    const outcome = await this.db.transaction(async (tx) => {
      await this.reports.lockReporter(input.reporterId, tx);
      const open = await this.cases.findOpen(input.targetType, input.targetId, tx);
      if (open) {
        const existing = await this.reports.findByReporterAndCase(input.reporterId, open.id, tx);
        if (existing) {
          return { kind: "already_reported", reportId: existing.id, caseId: open.id } as const;
        }
      }
      const recent = await this.reports.countRecent(input.reporterId, WINDOW_HOURS, tx);
      if (recent.total >= REPORT_LIMIT_PER_DAY) {
        return { kind: "limited", retryAfterS: Math.max(1, recent.secondsUntilOldestExpires ?? 1) } as const;
      }
      const reportCase = await this.cases.openOrGet(
        { targetType: input.targetType, targetId: input.targetId, targetUserId: input.targetUserId },
        tx,
      );
      const reportId = await this.reports.insert(
        {
          caseId: reportCase.id,
          reporterId: input.reporterId,
          reason: input.reason,
          note: checked.note,
          snapshot: { ...input.snapshot },
        },
        tx,
      );
      return { kind: "created", reportId, caseId: reportCase.id, caseOpened: reportCase.opened } as const;
    });

    if (outcome.kind === "limited") {
      throw new HttpException(
        {
          code: "report_limit_reached",
          message: `At most ${REPORT_LIMIT_PER_DAY} reports per 24 hours`,
          retryAfterS: outcome.retryAfterS,
        },
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
    if (outcome.kind === "created") {
      this.analytics.capture(ANALYTICS_EVENTS.REPORT_SUBMITTED, input.reporterId, {
        target_type: input.targetType,
        reason: input.reason,
      });
    }
    return outcome;
  }
}
