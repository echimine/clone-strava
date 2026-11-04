import { Inject, Injectable } from "@nestjs/common";
import { and, asc, count, desc, eq, gt, inArray, isNotNull, sql, type SQL } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import type { ReportCaseStatus, ReportReason, ReportTargetType } from "@repo/contracts";
import { DATABASE, type DbExecutor } from "../../infrastructure/index.js";
import type { CaseReportRecord } from "../domain/report-case.js";

/** Reads and writes on `moderation.report` only (ADR-021 §6, ADR-038 §9). */
@Injectable()
export class ReportRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  /** Serializes one reporter's Reports until the end of `tx`, so the 24 h limit holds under concurrency. */
  async lockReporter(reporterId: string, tx: DbExecutor): Promise<void> {
    await tx.execute(sql`select pg_advisory_xact_lock(hashtextextended(${`moderation.report:${reporterId}`}, 0))`);
  }

  async findByReporterAndCase(reporterId: string, caseId: string, executor: DbExecutor = this.db) {
    const [row] = await executor
      .select({ id: schema.report.id })
      .from(schema.report)
      .where(and(eq(schema.report.reporterId, reporterId), eq(schema.report.caseId, caseId)));
    return row;
  }

  /**
   * The reporter's Reports over the last `hours`, and the seconds until the oldest of them
   * leaves that window (null without any).
   */
  async countRecent(
    reporterId: string,
    hours: number,
    executor: DbExecutor,
  ): Promise<{ total: number; secondsUntilOldestExpires: number | null }> {
    const since = sql`now() - make_interval(hours => ${hours})`;
    const [row] = await executor
      .select({
        total: count(),
        secondsUntilOldestExpires: sql<
          string | null
        >`ceil(extract(epoch from (min(${schema.report.createdAt}) + make_interval(hours => ${hours}) - now())))`,
      })
      .from(schema.report)
      .where(and(eq(schema.report.reporterId, reporterId), gt(schema.report.createdAt, since)));
    return {
      total: row?.total ?? 0,
      secondsUntilOldestExpires:
        row?.secondsUntilOldestExpires === null || row?.secondsUntilOldestExpires === undefined
          ? null
          : Number(row.secondsUntilOldestExpires),
    };
  }

  async insert(
    values: {
      caseId: string;
      reporterId: string;
      reason: ReportReason;
      note: string | null;
      snapshot: Record<string, unknown>;
    },
    executor: DbExecutor,
  ): Promise<string> {
    const [row] = await executor.insert(schema.report).values(values).returning({ id: schema.report.id });
    return row!.id;
  }

  /** Erases the note of every Report `reporterId` sent (ADR-038 §13); returns how many. */
  async clearNotesOf(reporterId: string): Promise<number> {
    const rows = await this.db
      .update(schema.report)
      .set({ note: null })
      .where(and(eq(schema.report.reporterId, reporterId), isNotNull(schema.report.note)))
      .returning({ id: schema.report.id });
    return rows.length;
  }

  /** Reports on `userId` or their content (`received`), newest first. */
  findReceivedBy(userId: string, limit: number): Promise<UserReportRow[]> {
    return this.findForUser(eq(schema.reportCase.targetUserId, userId), limit);
  }

  /** Reports `userId` made (`sent`), newest first. */
  findSentBy(userId: string, limit: number): Promise<UserReportRow[]> {
    return this.findForUser(eq(schema.report.reporterId, userId), limit);
  }

  private findForUser(where: SQL, limit: number): Promise<UserReportRow[]> {
    return this.db
      .select({
        id: schema.report.id,
        caseId: schema.report.caseId,
        targetType: schema.reportCase.targetType,
        reason: schema.report.reason,
        status: schema.reportCase.status,
        createdAt: schema.report.createdAt,
      })
      .from(schema.report)
      .innerJoin(schema.reportCase, eq(schema.reportCase.id, schema.report.caseId))
      .where(where)
      .orderBy(desc(schema.report.createdAt), desc(schema.report.id))
      .limit(limit);
  }

  /** A case's Reports, oldest first. */
  findByCase(caseId: string): Promise<CaseReportRecord[]> {
    return this.db
      .select({
        id: schema.report.id,
        reporterId: schema.report.reporterId,
        reason: schema.report.reason,
        note: schema.report.note,
        createdAt: schema.report.createdAt,
        snapshot: schema.report.snapshot,
      })
      .from(schema.report)
      .where(eq(schema.report.caseId, caseId))
      .orderBy(asc(schema.report.createdAt), asc(schema.report.id));
  }

  /** Erases the copies of the cases' Reports (ADR-038 §9: on closing); the notes stay. Returns how many Reports. */
  async eraseSnapshots(caseIds: string[], executor: DbExecutor): Promise<number> {
    if (caseIds.length === 0) {
      return 0;
    }
    const rows = await executor
      .update(schema.report)
      .set({ snapshot: null })
      .where(inArray(schema.report.caseId, caseIds))
      .returning({ id: schema.report.id });
    return rows.length;
  }

  /** Reports on `userId` or their content, every case alike. */
  async countReceivedBy(userId: string): Promise<number> {
    const [row] = await this.db
      .select({ total: count() })
      .from(schema.report)
      .innerJoin(schema.reportCase, eq(schema.reportCase.id, schema.report.caseId))
      .where(eq(schema.reportCase.targetUserId, userId));
    return row?.total ?? 0;
  }

  /** What `reporterId` reported among `targetTypes`, open or closed cases alike. */
  findReportedTargets(
    reporterId: string,
    targetTypes: ReportTargetType[],
  ): Promise<{ targetType: ReportTargetType; targetId: string }[]> {
    return this.db
      .selectDistinct({ targetType: schema.reportCase.targetType, targetId: schema.reportCase.targetId })
      .from(schema.report)
      .innerJoin(schema.reportCase, eq(schema.reportCase.id, schema.report.caseId))
      .where(and(eq(schema.report.reporterId, reporterId), inArray(schema.reportCase.targetType, targetTypes)));
  }
}

/** A Report as the backoffice user sheet lists it (ADR-038 §5). */
export interface UserReportRow {
  id: string;
  caseId: string;
  targetType: ReportTargetType;
  reason: ReportReason;
  status: ReportCaseStatus;
  createdAt: Date;
}
