import { Inject, Injectable } from "@nestjs/common";
import { and, eq } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";

/** Reads and writes on `social.follow` only (ADR-021 §6). */
@Injectable()
export class FollowRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  findFolloweeIds(followerId: string) {
    return this.db.query.follow.findMany({
      where: and(
        eq(schema.follow.followerId, followerId),
        eq(schema.follow.status, "accepted"),
      ),
      columns: { followeeId: true },
    });
  }

  findOne(followerId: string, followeeId: string) {
    return this.db.query.follow.findFirst({
      where: and(
        eq(schema.follow.followerId, followerId),
        eq(schema.follow.followeeId, followeeId),
      ),
    });
  }
}
