import { Inject, Injectable } from "@nestjs/common";
import { eq, inArray } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";

/** Reads and writes on `users.user_profile` only (ADR-021 §6). */
@Injectable()
export class UserProfileRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  findById(userId: string) {
    return this.db.query.userProfile.findFirst({
      where: eq(schema.userProfile.userId, userId),
    });
  }

  findByIds(userIds: string[]) {
    if (userIds.length === 0) {
      return Promise.resolve([]);
    }
    return this.db.query.userProfile.findMany({
      where: inArray(schema.userProfile.userId, userIds),
    });
  }
}
