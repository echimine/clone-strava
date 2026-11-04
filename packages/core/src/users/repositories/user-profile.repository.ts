import { Inject, Injectable } from "@nestjs/common";
import { and, eq, inArray, ne, sql } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE, type DbExecutor, type Transaction } from "../../infrastructure/index.js";
import { escapeLikePattern } from "../domain/name-search.js";
import type { OnboardingProfileFields } from "../domain/onboarding-answers.js";
import type { ProfileDetailsFields } from "../domain/profile-details.js";

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

  /**
   * Ids of users whose `first_name last_name` contains `query`, ignoring
   * case and accents (`unaccent` + `ILIKE`, ADR-036 §2). Matches at the start
   * of a word come first, then alphabetical order. Rows without names never match.
   */
  async searchIdsByName(query: string, excludeUserId: string, limit: number): Promise<string[]> {
    const fullName = sql`unaccent(concat_ws(' ', ${t.firstName}, ${t.lastName}))`;
    const term = sql`unaccent(${escapeLikePattern(query)})`;
    const startsAWord = sql`(${fullName} ilike (${term} || '%')
      or ${fullName} ilike ('% ' || ${term} || '%')
      or ${fullName} ilike ('%-' || ${term} || '%'))`;
    const rows = await this.db
      .select({ userId: t.userId })
      .from(t)
      .where(and(ne(t.userId, excludeUserId), sql`${fullName} ilike ('%' || ${term} || '%')`))
      .orderBy(sql`${startsAWord} desc`, sql`lower(${fullName})`, t.userId)
      .limit(limit);
    return rows.map((row) => row.userId);
  }

  /** Creates the row with its defaults if it does not exist yet. */
  async insertIfAbsent(userId: string, executor: DbExecutor = this.db): Promise<void> {
    await executor.insert(t).values({ userId }).onConflictDoNothing({ target: t.userId });
  }

  /** Creates the row with these fields, or updates the existing one (ADR-036 §3). */
  async upsert(userId: string, fields: ProfileDetailsFields, executor: DbExecutor = this.db): Promise<void> {
    await executor
      .insert(t)
      .values({ userId, ...fields })
      .onConflictDoUpdate({ target: t.userId, set: { ...fields, updatedAt: new Date() } });
  }

  /** The Avatar key of an existing row, locked until the end of the transaction. */
  async lockAvatarKey(userId: string, tx: Transaction): Promise<string | null> {
    const [row] = await tx
      .select({ avatarKey: t.avatarKey })
      .from(t)
      .where(eq(t.userId, userId))
      .for("update");
    if (!row) {
      throw new Error(`No user_profile row for ${userId}`);
    }
    return row.avatarKey;
  }

  async setAvatarKey(userId: string, avatarKey: string | null, executor: DbExecutor = this.db): Promise<void> {
    await executor.update(t).set({ avatarKey, updatedAt: new Date() }).where(eq(t.userId, userId));
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
