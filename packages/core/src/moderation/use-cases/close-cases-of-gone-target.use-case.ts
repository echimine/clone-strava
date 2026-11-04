import { Inject, Injectable } from "@nestjs/common";
import type { ReportCaseStatus } from "@repo/contracts";
import type { Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";
import { goneTargetOutcome } from "../domain/report-case.js";
import { ReportCaseRepository, type GoneTargetScope } from "../repositories/report-case.repository.js";
import { ReportRepository } from "../repositories/report.repository.js";

/**
 * Automatic close when a target disappears (ADR-038 §10), whatever the path: a Sanction, a
 * deletion by the author, the author's account deleted. Author « Système », outcome
 * « Sanctionné » after a Sanction, else « Cible supprimée »; the copies are erased as on any
 * close. Idempotent: only open cases are touched. Each method returns the cases closed.
 */
@Injectable()
export class CloseCasesOfGoneTargetUseCase {
  constructor(
    @Inject(DATABASE) private readonly db: Database,
    private readonly cases: ReportCaseRepository,
    private readonly reports: ReportRepository,
  ) {}

  /** A comment or an Activity was deleted. */
  target(targetType: "comment" | "activity", targetId: string, bySanction: boolean): Promise<string[]> {
    return this.close({ kind: "target", targetType, targetId }, goneTargetOutcome(bySanction));
  }

  /** An Activity was deleted: its comments went with it (SQL cascade, no comment event). */
  commentsOfActivity(activityId: string): Promise<string[]> {
    return this.close({ kind: "commentsOfActivity", activityId }, "target_gone");
  }

  /** An account was deleted: the cascade took the athlete and all their content. */
  author(userId: string, bySanction: boolean): Promise<string[]> {
    return this.close({ kind: "author", userId }, goneTargetOutcome(bySanction));
  }

  private close(scope: GoneTargetScope, status: ReportCaseStatus): Promise<string[]> {
    return this.db.transaction(async (tx) => {
      const ids = await this.cases.closeOpen(scope, status, tx);
      await this.reports.eraseSnapshots(ids, tx);
      return ids;
    });
  }
}
