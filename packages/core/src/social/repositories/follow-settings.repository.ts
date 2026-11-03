import { Inject, Injectable } from "@nestjs/common";
import { eq, sql } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE, type DbExecutor } from "../../infrastructure/index.js";

/** Reads and writes on `social.follow_settings` only (ADR-021 §6, ADR-036 §1). */
@Injectable()
export class FollowSettingsRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  /** "Approuver mes abonnés"; no row means `false`. */
  async approvesFollowers(userId: string, executor: DbExecutor = this.db): Promise<boolean> {
    const [row] = await executor
      .select({ approveFollowers: schema.followSettings.approveFollowers })
      .from(schema.followSettings)
      .where(eq(schema.followSettings.userId, userId));
    return row?.approveFollowers ?? false;
  }

  async upsert(userId: string, approveFollowers: boolean, executor: DbExecutor = this.db): Promise<void> {
    await executor
      .insert(schema.followSettings)
      .values({ userId, approveFollowers })
      .onConflictDoUpdate({
        target: schema.followSettings.userId,
        set: { approveFollowers, updatedAt: sql`now()` },
      });
  }
}
