import { Inject, Injectable } from "@nestjs/common";
import { eq, inArray, sql } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE, type DbExecutor, type Transaction } from "../../infrastructure/index.js";
import type { OnboardingProfileFields } from "../domain/onboarding-answers.js";

const t = schema.userProfile;

/** Reads and writes on `users.user_profile` only (ADR-021 §6). */
@Injectable()
export class UserProfileRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  findById(userId: string) {
    return this.db.query.userProfile.findFirst({
      where: eq(t.userId, userId),
    });
  }

  findByIds(userIds: string[]) {
    if (userIds.length === 0) {
      return Promise.resolve([]);
    }
    return this.db.query.userProfile.findMany({
      where: inArray(t.userId, userIds),
    });
  }

  /** Creates the row with its defaults if it does not exist yet. */
  async insertIfAbsent(userId: string, executor: DbExecutor = this.db): Promise<void> {
    await executor.insert(t).values({ userId }).onConflictDoNothing({ target: t.userId });
  }

  /** The Onboarding fields of an existing row, locked until the end of the transaction. */
  async lockOnboardingFields(userId: string, tx: Transaction): Promise<OnboardingProfileFields> {
    const [row] = await tx
      .select({
        firstName: t.firstName,
        lastName: t.lastName,
        birthDate: t.birthDate,
        gender: t.gender,
        level: t.level,
        // `node-pg` does not parse arrays of a custom enum type: only `null` matters here.
        goals: sql<string[] | null>`${t.goals}::text[]`,
      })
      .from(t)
      .where(eq(t.userId, userId))
      .for("update");
    if (!row) {
      throw new Error(`No user_profile row for ${userId}`);
    }
    return { ...row, goals: row.goals as OnboardingProfileFields["goals"] };
  }

  async update(userId: string, fields: Partial<OnboardingProfileFields>, executor: DbExecutor = this.db) {
    await executor
      .update(t)
      .set({ ...fields, updatedAt: new Date() })
      .where(eq(t.userId, userId));
  }
}
