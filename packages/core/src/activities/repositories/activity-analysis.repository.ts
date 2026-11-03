import { Inject, Injectable } from "@nestjs/common";
import { eq } from "drizzle-orm";
import { activityAnalysisSchema, type ActivityAnalysis } from "@repo/contracts";
import { schema, type Database } from "@repo/db";
import { DATABASE, type DbExecutor } from "../../infrastructure/index.js";

/** Reads and writes on `activities.activity_analysis` only (ADR-021 §6, ADR-036 §6). */
@Injectable()
export class ActivityAnalysisRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  /** The stored analysis and its version, undefined when not computed yet. */
  async findByActivityId(
    activityId: string,
  ): Promise<{ version: number; analysis: ActivityAnalysis } | undefined> {
    const [row] = await this.db
      .select()
      .from(schema.activityAnalysis)
      .where(eq(schema.activityAnalysis.activityId, activityId));
    if (!row) {
      return undefined;
    }
    // jsonb written by `upsert` only; parsed so a malformed row never reaches the contract.
    const parsed = activityAnalysisSchema.safeParse({ splits: row.splits, series: row.series });
    return {
      version: row.version,
      analysis: parsed.success ? parsed.data : { splits: [], series: null },
    };
  }

  /** Upsert, in the processing transaction (ADR-036 §6). */
  async upsert(
    activityId: string,
    version: number,
    analysis: ActivityAnalysis,
    executor: DbExecutor = this.db,
  ): Promise<void> {
    const values = {
      activityId,
      version,
      splits: analysis.splits,
      series: analysis.series,
      computedAt: new Date(),
    };
    const { activityId: _activityId, ...updates } = values;
    await executor
      .insert(schema.activityAnalysis)
      .values(values)
      .onConflictDoUpdate({ target: schema.activityAnalysis.activityId, set: updates });
  }
}
