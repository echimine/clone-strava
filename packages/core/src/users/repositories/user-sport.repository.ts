import { Inject, Injectable } from "@nestjs/common";
import { asc, eq } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE, type DbExecutor } from "../../infrastructure/index.js";

const t = schema.userSport;

/** Reads and writes on `users.user_sport` only (ADR-021 §6, ADR-035 §4). */
@Injectable()
export class UserSportRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  async hasAny(userId: string, executor: DbExecutor = this.db): Promise<boolean> {
    const rows = await executor.select({ userId: t.userId }).from(t).where(eq(t.userId, userId)).limit(1);
    return rows.length > 0;
  }

  /** The athlete's Practiced sports, in the order of selection. */
  async findCodes(userId: string): Promise<string[]> {
    const rows = await this.db
      .select({ sportCode: t.sportCode })
      .from(t)
      .where(eq(t.userId, userId))
      .orderBy(asc(t.position));
    return rows.map((row) => row.sportCode);
  }

  /** `sportCodes` in the order of selection, stored as `position` 0, 1, ... */
  async insertAll(userId: string, sportCodes: string[], executor: DbExecutor = this.db): Promise<void> {
    await executor.insert(t).values(
      sportCodes.map((sportCode, position) => ({
        userId,
        sportCode,
        position,
      })),
    );
  }
}
