import { Inject, Injectable } from "@nestjs/common";
import { and, count, desc, eq, lt, sql } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE, type DbExecutor } from "../../infrastructure/index.js";

export type ActivityImportRow = typeof schema.activityImport.$inferSelect;
type ImportStatus = (typeof schema.importStatusEnum.enumValues)[number];

/** Reads and writes on `activities.activity_import` only (ADR-021 §6, ADR-028 §1). */
@Injectable()
export class ActivityImportRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  findById(id: string): Promise<ActivityImportRow | undefined> {
    return this.db.query.activityImport.findFirst({ where: eq(schema.activityImport.id, id) });
  }

  /** Inserts a new import; `false` when the id already exists (replayed `POST`, ADR-028 §3). */
  async insertIfAbsent(values: typeof schema.activityImport.$inferInsert): Promise<boolean> {
    const inserted = await this.db
      .insert(schema.activityImport)
      .values(values)
      .onConflictDoNothing({ target: schema.activityImport.id })
      .returning({ id: schema.activityImport.id });
    return inserted.length > 0;
  }

  async listByUser(userId: string, options: { status?: ImportStatus; page: number; limit: number }) {
    const where = options.status
      ? and(eq(schema.activityImport.userId, userId), eq(schema.activityImport.status, options.status))
      : eq(schema.activityImport.userId, userId);
    const [items, [totalRow]] = await Promise.all([
      this.db
        .select()
        .from(schema.activityImport)
        .where(where)
        .orderBy(desc(schema.activityImport.createdAt))
        .limit(options.limit)
        .offset((options.page - 1) * options.limit),
      this.db.select({ total: count() }).from(schema.activityImport).where(where),
    ]);
    return { items, total: totalRow?.total ?? 0 };
  }

  /** The `imported` import of this user with the same content, if any (ADR-028 §6 step 1). */
  findImportedBySha256(userId: string, sha256: string) {
    return this.db.query.activityImport.findFirst({
      where: and(
        eq(schema.activityImport.userId, userId),
        eq(schema.activityImport.sha256, sha256),
        eq(schema.activityImport.status, "imported"),
      ),
    });
  }

  /** `pending` -> `processing` (ADR-028 §3 `complete`); `false` if it was not `pending`. */
  async markProcessingIfPending(id: string): Promise<boolean> {
    const updated = await this.db
      .update(schema.activityImport)
      .set({ status: "processing" })
      .where(and(eq(schema.activityImport.id, id), eq(schema.activityImport.status, "pending")))
      .returning({ id: schema.activityImport.id });
    return updated.length > 0;
  }

  /** `failed` -> `processing` (backoffice reprocessing, ADR-028 §7); `false` if it was not `failed`. */
  async resetFailedToProcessing(id: string): Promise<boolean> {
    const updated = await this.db
      .update(schema.activityImport)
      .set({ status: "processing", error: null, processedAt: null })
      .where(and(eq(schema.activityImport.id, id), eq(schema.activityImport.status, "failed")))
      .returning({ id: schema.activityImport.id });
    return updated.length > 0;
  }

  async incrementAttempts(id: string): Promise<void> {
    await this.db
      .update(schema.activityImport)
      .set({ attempts: sql`${schema.activityImport.attempts} + 1` })
      .where(eq(schema.activityImport.id, id));
  }

  async markImported(
    id: string,
    values: { activityId: string; sha256: string },
    executor: DbExecutor = this.db,
  ): Promise<void> {
    await executor
      .update(schema.activityImport)
      .set({ status: "imported", ...values, error: null, processedAt: new Date() })
      .where(eq(schema.activityImport.id, id));
  }

  async markDuplicate(id: string, values: { activityId: string; sha256: string }): Promise<void> {
    await this.db
      .update(schema.activityImport)
      .set({ status: "duplicate", ...values, error: null, processedAt: new Date() })
      .where(eq(schema.activityImport.id, id));
  }

  async markFailed(id: string, errorCode: string, sha256?: string): Promise<void> {
    await this.db
      .update(schema.activityImport)
      .set({ status: "failed", error: errorCode, sha256, processedAt: new Date() })
      .where(eq(schema.activityImport.id, id));
  }

  /** ADR-028 §8: `activity_import_status_idx` (partial index on in-flight statuses). */
  findStuckProcessing(olderThanMinutes: number, limit = 100) {
    return this.db
      .select({ id: schema.activityImport.id, userId: schema.activityImport.userId })
      .from(schema.activityImport)
      .where(
        and(
          eq(schema.activityImport.status, "processing"),
          lt(schema.activityImport.createdAt, sql`now() - make_interval(mins => ${olderThanMinutes})`),
        ),
      )
      .limit(limit);
  }
}
