import { Inject, Injectable } from "@nestjs/common";
import { eq } from "drizzle-orm";
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
