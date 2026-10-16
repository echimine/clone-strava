import { Inject, Injectable } from "@nestjs/common";
import { and, count, eq, inArray } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";

/** Reads and writes on `engagement.kudos` only (ADR-021 §6). */
@Injectable()
export class KudosRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  findOne(userId: string, activityId: string) {
    return this.db.query.kudos.findFirst({
      where: and(eq(schema.kudos.userId, userId), eq(schema.kudos.activityId, activityId)),
    });
  }

  async countByActivityIds(activityIds: string[]): Promise<Map<string, number>> {
    if (activityIds.length === 0) {
      return new Map();
    }
    const rows = await this.db
      .select({ activityId: schema.kudos.activityId, total: count() })
      .from(schema.kudos)
      .where(inArray(schema.kudos.activityId, activityIds))
      .groupBy(schema.kudos.activityId);
    return new Map(rows.map((row) => [row.activityId, row.total]));
  }

  /** The subset of `activityIds` the user gave kudos to. */
  async findKudoedActivityIds(userId: string, activityIds: string[]): Promise<Set<string>> {
    if (activityIds.length === 0) {
      return new Set();
    }
    const rows = await this.db
      .select({ activityId: schema.kudos.activityId })
      .from(schema.kudos)
      .where(and(eq(schema.kudos.userId, userId), inArray(schema.kudos.activityId, activityIds)));
    return new Set(rows.map((row) => row.activityId));
  }

  /** Idempotent: giving kudos twice keeps one row. Returns whether a row was inserted. */
  async give(userId: string, activityId: string): Promise<boolean> {
    const inserted = await this.db
      .insert(schema.kudos)
      .values({ userId, activityId })
      .onConflictDoNothing()
      .returning({ userId: schema.kudos.userId });
    return inserted.length > 0;
  }

  /** Idempotent: removing missing kudos is a no-op. Returns whether a row was deleted. */
  async remove(userId: string, activityId: string): Promise<boolean> {
    const deleted = await this.db
      .delete(schema.kudos)
      .where(and(eq(schema.kudos.userId, userId), eq(schema.kudos.activityId, activityId)))
      .returning({ userId: schema.kudos.userId });
    return deleted.length > 0;
  }
}
