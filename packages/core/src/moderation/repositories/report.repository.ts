import { Inject, Injectable } from "@nestjs/common";
import { and, count, eq, gt, inArray, sql } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import type { ReportReason, ReportTargetType } from "@repo/contracts";
import { DATABASE, type DbExecutor } from "../../infrastructure/index.js";

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
