import { Inject, Injectable } from "@nestjs/common";
import { and, asc, count, desc, eq, gte, inArray, lt, min, ne, sql, type SQL } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import type { ReportCaseStatus, ReportReason, ReportTargetType } from "@repo/contracts";
import { DATABASE, notByUsers, offsetPage, parisDayRange, type DbExecutor } from "../../infrastructure/index.js";
import type { ReportCaseFilter, ReportCaseRecord, ReportCaseRow } from "../domain/report-case.js";

const t = schema.reportCase;

/**
 * The outer case's id inside a correlated subquery over `moderation.report r`: drizzle writes a
 * single-table query's columns unqualified, and a bare `"id"` there would be `r.id`.
 */
const caseId = sql.raw(`"report_case"."id"`);

/** Reports of the case, counted. */
const reportCount = sql<number>`(select count(*)::int from moderation.report r where r.case_id = ${caseId})`;
/** Distinct reasons of the case's Reports, in the enum's order (as JSON: no enum-array parsing). */
const reasons = sql<ReportReason[]>`(select coalesce(json_agg(x.reason order by x.reason), '[]'::json)
  from (select distinct r.reason from moderation.report r where r.case_id = ${caseId}) x)`;
/** The first Report's copy. */
const firstSnapshot = sql<Record<string, unknown> | null>`(select r.snapshot from moderation.report r
  where r.case_id = ${caseId} order by r.created_at, r.id limit 1)`;

/** Reads and writes on `moderation.report_case` only (ADR-021 §6, ADR-038 §10). */
@Injectable()
export class ReportCaseRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  /** The target's open case, if any (at most one, `report_case_open_target_idx`). */
  async findOpen(targetType: ReportTargetType, targetId: string, executor: DbExecutor = this.db) {
    const [row] = await executor
      .select({ id: schema.reportCase.id })
      .from(schema.reportCase)
      .where(
        and(
          eq(schema.reportCase.targetType, targetType),
          eq(schema.reportCase.targetId, targetId),
          eq(schema.reportCase.status, "open"),
        ),
      );
    return row;
  }

  /**
   * Opens the target's case, or returns the one another Report just opened (the partial unique
   * index settles a race). `opened` tells which.
   */
  async openOrGet(
    values: { targetType: ReportTargetType; targetId: string; targetUserId: string },
    executor: DbExecutor,
  ): Promise<{ id: string; opened: boolean }> {
    const [inserted] = await executor
      .insert(schema.reportCase)
      .values(values)
      .onConflictDoNothing({
        target: [schema.reportCase.targetType, schema.reportCase.targetId],
        where: sql`${schema.reportCase.status} = 'open'`,
      })
      .returning({ id: schema.reportCase.id });
    if (inserted) {
      return { id: inserted.id, opened: true };
    }
    const open = await this.findOpen(values.targetType, values.targetId, executor);
    if (!open) {
      throw new Error("The target's open case vanished while a Report joined it");
    }
    return { id: open.id, opened: false };
  }

  async findById(id: string): Promise<ReportCaseRecord | undefined> {
    const [row] = await this.db.select().from(t).where(eq(t.id, id));
    return row;
  }

  /** The ids among `ids` of cases that exist (Journal links). */
  async findExistingIds(ids: string[]): Promise<Set<string>> {
    if (ids.length === 0) {
      return new Set();
    }
    const rows = await this.db.select({ id: t.id }).from(t).where(inArray(t.id, ids));
    return new Set(rows.map((row) => row.id));
  }

  /**
   * One page of the queue (ADR-038 §10). By the opening (oldest first by default), then the most
   * reported; by the Report count, then the oldest; by the closing, newest first unless `asc`.
   */
  async findPage(
    filter: ReportCaseFilter,
    page: { page: number; pageSize: number },
  ): Promise<{ rows: ReportCaseRow[]; total: number }> {
    const where = and(...this.conditions(filter));
    const { limit, offset } = offsetPage(page);
    const direction = filter.order === "asc" ? asc : desc;
    const order: SQL[] =
      filter.sort === "reportCount"
        ? [direction(reportCount), asc(t.openedAt)]
        : filter.sort === "closedAt"
          ? [sql`${t.closedAt} ${sql.raw(filter.order)} nulls last`, desc(reportCount)]
          : [direction(t.openedAt), desc(reportCount)];
    const [rows, [counted]] = await Promise.all([
      this.db
        .select({
          id: t.id,
          targetType: t.targetType,
          targetId: t.targetId,
          targetUserId: t.targetUserId,
          status: t.status,
          openedAt: t.openedAt,
          closedAt: t.closedAt,
          closedBy: t.closedBy,
          closeNote: t.closeNote,
          reportCount,
          reasons,
          firstSnapshot,
        })
        .from(t)
        .where(where)
        .orderBy(...order, asc(t.id))
        .limit(limit)
        .offset(offset),
      this.db.select({ total: count() }).from(t).where(where),
    ]);
    return { rows, total: counted?.total ?? 0 };
  }

  /**
   * Open cases and when the oldest was opened (the dashboard's « À traiter » tile), but those
   * whose target belongs to one of `excludedUserIds`.
   */
  async countOpen(excludedUserIds: readonly string[]): Promise<{ count: number; oldestOpenedAt: Date | null }> {
    const [row] = await this.db
      .select({ count: count(), oldestOpenedAt: min(t.openedAt) })
      .from(t)
      .where(and(eq(t.status, "open"), notByUsers(t.targetUserId, excludedUserIds)));
    return { count: row?.count ?? 0, oldestOpenedAt: row?.oldestOpenedAt ?? null };
  }

  /** Closes the case if still open; undefined when it was not open (or does not exist). */
  async closeIfOpen(
    id: string,
    values: { status: ReportCaseStatus; closedBy: string | null; closeNote: string | null },
    executor: DbExecutor,
  ): Promise<{ id: string; status: ReportCaseStatus; closedAt: Date } | undefined> {
    const [row] = await executor
      .update(t)
      .set({ ...values, closedAt: sql`now()` })
      .where(and(eq(t.id, id), eq(t.status, "open")))
      .returning({ id: t.id, status: t.status, closedAt: t.closedAt });
    return row ? { id: row.id, status: row.status, closedAt: row.closedAt! } : undefined;
  }

  /** Closes, by « Système », every open case of `scope`; returns their ids. */
  async closeOpen(scope: GoneTargetScope, status: ReportCaseStatus, executor: DbExecutor): Promise<string[]> {
    const rows = await executor
      .update(t)
      .set({ status, closedAt: sql`now()`, closedBy: null, closeNote: null })
      .where(and(eq(t.status, "open"), scopeCondition(scope)))
      .returning({ id: t.id });
    return rows.map((row) => row.id);
  }

  private conditions(filter: ReportCaseFilter): SQL[] {
    const { start, end } = parisDayRange(filter);
    return [
      filter.state === "open" ? eq(t.status, "open") : ne(t.status, "open"),
      filter.targetType ? eq(t.targetType, filter.targetType) : undefined,
      filter.reason
        ? sql`exists (select 1 from moderation.report r where r.case_id = ${caseId} and r.reason = ${filter.reason})`
        : undefined,
      start ? gte(t.openedAt, start) : undefined,
      end ? lt(t.openedAt, end) : undefined,
    ].filter((condition): condition is SQL => condition !== undefined);
  }
}

/**
 * Cases whose target disappeared: a comment or an Activity; the comments of a deleted Activity
 * (found through the Reports' copies, ADR-038 §9); everything of a deleted account.
 */
export type GoneTargetScope =
  | { kind: "target"; targetType: ReportTargetType; targetId: string }
  | { kind: "commentsOfActivity"; activityId: string }
  | { kind: "author"; userId: string };

function scopeCondition(scope: GoneTargetScope): SQL {
  switch (scope.kind) {
    case "target":
      return and(eq(t.targetType, scope.targetType), eq(t.targetId, scope.targetId))!;
    case "commentsOfActivity":
      return sql`${t.targetType} = 'comment' and exists (select 1 from moderation.report r
        where r.case_id = ${caseId} and r.snapshot->>'activityId' = ${scope.activityId})`;
    case "author":
      return eq(t.targetUserId, scope.userId);
  }
}
