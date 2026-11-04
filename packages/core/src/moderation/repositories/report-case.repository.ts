import { Inject, Injectable } from "@nestjs/common";
import { and, eq, sql } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import type { ReportTargetType } from "@repo/contracts";
import { DATABASE, type DbExecutor } from "../../infrastructure/index.js";

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
}
