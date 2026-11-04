import { ConflictException, Inject, Injectable, NotFoundException } from "@nestjs/common";
import { ADMIN_REPORT_ERROR_CODES } from "@repo/contracts";
import type { Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";
import type { ClosedCase, ManualCaseOutcome } from "../domain/report-case.js";
import { ReportCaseRepository } from "../repositories/report-case.repository.js";
import { ReportRepository } from "../repositories/report.repository.js";

/**
 * « Clore » (ADR-038 §10): an Administrator closes a case as « Sanctionné » (`actioned`) or
 * « Rejeter » (`dismissed`), with an optional note. Every Report of the case closes with it and
 * loses its copy of the texts; the reporters' notes stay. `404 report_case_not_found`, `409
 * case_closed` when it is no longer open. Whether a Sanction allows « Sanctionné » is checked by
 * the caller, which reads the Journal.
 */
@Injectable()
export class CloseReportCaseUseCase {
  constructor(
    @Inject(DATABASE) private readonly db: Database,
    private readonly cases: ReportCaseRepository,
    private readonly reports: ReportRepository,
  ) {}

  async execute(
    caseId: string,
    outcome: ManualCaseOutcome,
    closedBy: string,
    note: string | null,
  ): Promise<ClosedCase> {
    const closed = await this.db.transaction(async (tx) => {
      const row = await this.cases.closeIfOpen(caseId, { status: outcome, closedBy, closeNote: note }, tx);
      if (!row) {
        return undefined;
      }
      const count = await this.reports.eraseSnapshots([caseId], tx);
      return { ...row, count };
    });
    if (closed) {
      return closed;
    }
    if (!(await this.cases.findById(caseId))) {
      throw new NotFoundException({ code: ADMIN_REPORT_ERROR_CODES.notFound, message: "Report case not found" });
    }
    throw new ConflictException({ code: ADMIN_REPORT_ERROR_CODES.closed, message: "The case is already closed" });
  }
}
