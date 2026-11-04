import { Inject, Injectable } from "@nestjs/common";
import { and, count, desc, eq, sql, type SQL } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE, offsetPage } from "../../infrastructure/index.js";
import type { FailedActivityRow, FailedImportRow, FailurePage, StaleActivityRow } from "../domain/admin-failure.js";

type Page = { page: number; pageSize: number };

/**
 * The failures of the Jobs screen's "Échecs" tab (ADR-038 §14), newest first: `failed`
 * Activities, `failed` imports and failed recomputations (processed Activities whose official
 * values were computed for another sport, the same rule as the reconciliation, ADR-033 §5).
 * The `*Ids` reads give what a batch relaunches, in the order of the list.
 */
@Injectable()
export class AdminFailureRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  async findFailedActivities(page: Page): Promise<FailurePage<FailedActivityRow>> {
    const a = schema.activity;
    const { limit, offset } = offsetPage(page);
    const rows = this.db
      .select({
        id: a.id,
        userId: a.userId,
        title: a.title,
        sportTypeCode: a.sportTypeCode,
        processingError: a.processingError,
        processingAttempts: a.processingAttempts,
        startedAt: a.startedAt,
        createdAt: a.createdAt,
      })
      .from(a)
      .where(this.failedActivity())
      .orderBy(desc(a.createdAt), desc(a.id))
      .limit(limit)
      .offset(offset);
    const total = this.db.select({ total: count() }).from(a).where(this.failedActivity());
    return this.page(rows, total);
  }

  async findFailedActivityIds(limit: number): Promise<string[]> {
    const a = schema.activity;
    const rows = await this.db
      .select({ id: a.id })
      .from(a)
      .where(this.failedActivity())
      .orderBy(desc(a.createdAt), desc(a.id))
      .limit(limit);
    return rows.map((row) => row.id);
  }

  async findFailedImports(page: Page): Promise<FailurePage<FailedImportRow>> {
    const i = schema.activityImport;
    const { limit, offset } = offsetPage(page);
    const rows = this.db
      .select({
        id: i.id,
        userId: i.userId,
        format: i.format,
        fileName: i.originalFileName,
        error: i.error,
        attempts: i.attempts,
        createdAt: i.createdAt,
        processedAt: i.processedAt,
      })
      .from(i)
      .where(eq(i.status, "failed"))
      .orderBy(desc(i.createdAt), desc(i.id))
      .limit(limit)
      .offset(offset);
    const total = this.db.select({ total: count() }).from(i).where(eq(i.status, "failed"));
    // `error` holds one of the ADR-028 §7 codes, written by the import use case only.
    return this.page(rows as Promise<FailedImportRow[]>, total);
  }

  async findFailedImportIds(limit: number): Promise<string[]> {
    const i = schema.activityImport;
    const rows = await this.db
      .select({ id: i.id })
      .from(i)
      .where(eq(i.status, "failed"))
      .orderBy(desc(i.createdAt), desc(i.id))
      .limit(limit);
    return rows.map((row) => row.id);
  }

  async findStaleActivities(page: Page): Promise<FailurePage<StaleActivityRow>> {
    const a = schema.activity;
    const { limit, offset } = offsetPage(page);
    const rows = this.db
      .select({
        id: a.id,
        userId: a.userId,
        title: a.title,
        sportTypeCode: a.sportTypeCode,
        computedForSportTypeCode: schema.activityStats.computedForSportTypeCode,
        startedAt: a.startedAt,
        updatedAt: a.updatedAt,
      })
      .from(a)
      .innerJoin(schema.activityStats, eq(schema.activityStats.activityId, a.id))
      .where(this.staleActivity())
      .orderBy(desc(a.updatedAt), desc(a.id))
      .limit(limit)
      .offset(offset);
    const total = this.db
      .select({ total: count() })
      .from(a)
      .innerJoin(schema.activityStats, eq(schema.activityStats.activityId, a.id))
      .where(this.staleActivity());
    return this.page(rows, total);
  }

  async findStaleActivityIds(limit: number): Promise<string[]> {
    const a = schema.activity;
    const rows = await this.db
      .select({ id: a.id })
      .from(a)
      .innerJoin(schema.activityStats, eq(schema.activityStats.activityId, a.id))
      .where(this.staleActivity())
      .orderBy(desc(a.updatedAt), desc(a.id))
      .limit(limit);
    return rows.map((row) => row.id);
  }

  /** The Activity if its official values are stale, with its author. */
  async findStaleActivity(id: string): Promise<{ id: string; userId: string } | undefined> {
    const a = schema.activity;
    const [row] = await this.db
      .select({ id: a.id, userId: a.userId })
      .from(a)
      .innerJoin(schema.activityStats, eq(schema.activityStats.activityId, a.id))
      .where(and(eq(a.id, id), this.staleActivity()));
    return row;
  }

  private failedActivity(): SQL {
    return eq(schema.activity.processingStatus, "failed");
  }

  private staleActivity(): SQL {
    return and(
      eq(schema.activity.processingStatus, "processed"),
      sql`${schema.activityStats.computedForSportTypeCode} is distinct from ${schema.activity.sportTypeCode}`,
    )!;
  }

  private async page<Row>(rows: Promise<Row[]>, total: Promise<{ total: number }[]>): Promise<FailurePage<Row>> {
    const [items, [counted]] = await Promise.all([rows, total]);
    return { rows: items, total: counted?.total ?? 0 };
  }
}
