import { Inject, Injectable } from "@nestjs/common";
import { and, desc, eq, gt, inArray, lt, ne, or, sql } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE, type DbExecutor } from "../../infrastructure/index.js";

type ProcessingStatus = (typeof schema.processingStatusEnum.enumValues)[number];

/** Reads and writes on `activities.activity` only (ADR-021 §6). */
@Injectable()
export class ActivityRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  findById(id: string) {
    return this.db.query.activity.findFirst({ where: eq(schema.activity.id, id) });
  }

  findByIds(ids: string[]) {
    if (ids.length === 0) {
      return Promise.resolve([]);
    }
    return this.db.query.activity.findMany({ where: inArray(schema.activity.id, ids) });
  }

  /**
   * One feed page (ADR-029): the viewer's own processed activities plus the
   * `public`/`followers` ones of their followees, keyset-paginated on
   * `(started_at desc, id desc)`. Returns up to `limit + 1` rows so the
   * caller knows whether a next page exists.
   */
  findFeedPage(params: {
    viewerId: string;
    followeeIds: string[];
    before?: { startedAt: Date; id: string };
    limit: number;
  }) {
    const { viewerId, followeeIds, before, limit } = params;
    const authors =
      followeeIds.length === 0
        ? eq(schema.activity.userId, viewerId)
        : or(
            eq(schema.activity.userId, viewerId),
            and(
              inArray(schema.activity.userId, followeeIds),
              inArray(schema.activity.visibility, ["public", "followers"]),
            ),
          );
    return this.db
      .select()
      .from(schema.activity)
      .where(
        and(
          authors,
          eq(schema.activity.processingStatus, "processed"),
          before
            ? sql`(${schema.activity.startedAt}, ${schema.activity.id}) < (${before.startedAt.toISOString()}::timestamptz, ${before.id}::uuid)`
            : undefined,
        ),
      )
      .orderBy(desc(schema.activity.startedAt), desc(schema.activity.id))
      .limit(limit + 1);
  }

  /** ADR-019 §7: `activity_processing_status_idx` (partial index, status != 'processed'). */
  findStuckProcessing(olderThanMinutes: number, limit = 100) {
    return this.db
      .select({ id: schema.activity.id, userId: schema.activity.userId })
      .from(schema.activity)
      .where(
        and(
          eq(schema.activity.processingStatus, "processing"),
          lt(schema.activity.createdAt, sql`now() - make_interval(mins => ${olderThanMinutes})`),
        ),
      )
      .limit(limit);
  }

  /**
   * The user's activities whose time interval intersects `[startedAt,
   * endedAt]`, failed ones excluded (ADR-028 §6). Uses
   * `activity_user_started_at_idx`; the overlap ratio is computed by the caller.
   */
  findOverlapping(userId: string, startedAt: Date, endedAt: Date) {
    return this.db
      .select({
        id: schema.activity.id,
        startedAt: schema.activity.startedAt,
        endedAt: schema.activity.endedAt,
      })
      .from(schema.activity)
      .where(
        and(
          eq(schema.activity.userId, userId),
          ne(schema.activity.processingStatus, "failed"),
          lt(schema.activity.startedAt, endedAt),
          gt(schema.activity.endedAt, startedAt),
        ),
      );
  }

  /**
   * Idempotent insert (ADR-019 §1, ADR-028 §1: a replayed `POST` or import
   * job inserts nothing); `false` when the id already exists.
   */
  async insertIfAbsent(
    values: typeof schema.activity.$inferInsert,
    executor: DbExecutor = this.db,
  ): Promise<boolean> {
    const inserted = await executor
      .insert(schema.activity)
      .values(values)
      .onConflictDoNothing({ target: schema.activity.id })
      .returning({ id: schema.activity.id });
    return inserted.length > 0;
  }

  /** `pending` -> `processing` (ADR-019 §4 `complete`); `false` if it was not `pending`. */
  async markProcessingIfPending(id: string): Promise<boolean> {
    const updated = await this.db
      .update(schema.activity)
      .set({ processingStatus: "processing" })
      .where(and(eq(schema.activity.id, id), eq(schema.activity.processingStatus, "pending")))
      .returning({ id: schema.activity.id });
    return updated.length > 0;
  }

  async incrementAttempts(id: string): Promise<void> {
    await this.db
      .update(schema.activity)
      .set({ processingAttempts: sql`${schema.activity.processingAttempts} + 1` })
      .where(eq(schema.activity.id, id));
  }

  async markProcessed(id: string, executor: DbExecutor = this.db): Promise<void> {
    await executor
      .update(schema.activity)
      .set({ processingStatus: "processed", processingError: null, processedAt: new Date() })
      .where(eq(schema.activity.id, id));
  }

  async markFailed(id: string, errorCode: string): Promise<void> {
    await this.db
      .update(schema.activity)
      .set({ processingStatus: "failed", processingError: errorCode, processedAt: new Date() })
      .where(eq(schema.activity.id, id));
  }

  async updateStatus(id: string, status: ProcessingStatus): Promise<void> {
    await this.db
      .update(schema.activity)
      .set({ processingStatus: status })
      .where(eq(schema.activity.id, id));
  }
}
