import { Inject, Injectable } from "@nestjs/common";
import { and, desc, eq, or } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE, type DbExecutor } from "../../infrastructure/index.js";

/** Reads and writes on `social.athlete_block` only (ADR-021 §6, ADR-038 §8). */
@Injectable()
export class AthleteBlockRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  /** Idempotent: an existing Block is left as is (its date too). */
  async insertIfAbsent(blockerId: string, blockedId: string, executor: DbExecutor = this.db): Promise<void> {
    await executor.insert(schema.athleteBlock).values({ blockerId, blockedId }).onConflictDoNothing();
  }

  /** Idempotent. */
  async delete(blockerId: string, blockedId: string): Promise<void> {
    await this.db
      .delete(schema.athleteBlock)
      .where(and(eq(schema.athleteBlock.blockerId, blockerId), eq(schema.athleteBlock.blockedId, blockedId)));
  }

  /** The athletes `blockerId` blocked, most recent first. */
  findBlockedBy(blockerId: string): Promise<{ athleteId: string; createdAt: Date }[]> {
    return this.db
      .select({ athleteId: schema.athleteBlock.blockedId, createdAt: schema.athleteBlock.createdAt })
      .from(schema.athleteBlock)
      .where(eq(schema.athleteBlock.blockerId, blockerId))
      .orderBy(desc(schema.athleteBlock.createdAt), desc(schema.athleteBlock.blockedId));
  }

  /** Athletes `userId` blocked or who blocked `userId`, without duplicates. */
  async findBlockedEitherWay(userId: string): Promise<string[]> {
    const rows = await this.db
      .select({ blockerId: schema.athleteBlock.blockerId, blockedId: schema.athleteBlock.blockedId })
      .from(schema.athleteBlock)
      .where(or(eq(schema.athleteBlock.blockerId, userId), eq(schema.athleteBlock.blockedId, userId)));
    return [...new Set(rows.map((row) => (row.blockerId === userId ? row.blockedId : row.blockerId)))];
  }

  /** Whether either athlete blocked the other. */
  async existsBetween(a: string, b: string): Promise<boolean> {
    const [row] = await this.db
      .select({ blockerId: schema.athleteBlock.blockerId })
      .from(schema.athleteBlock)
      .where(
        or(
          and(eq(schema.athleteBlock.blockerId, a), eq(schema.athleteBlock.blockedId, b)),
          and(eq(schema.athleteBlock.blockerId, b), eq(schema.athleteBlock.blockedId, a)),
        ),
      )
      .limit(1);
    return row !== undefined;
  }
}
