import { Inject, Injectable, NotImplementedException } from "@nestjs/common";
import { and, eq } from "drizzle-orm";
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

  countByActivityIds(_activityIds: string[]): Promise<Map<string, number>> {
    throw new NotImplementedException();
  }

  async give(_userId: string, _activityId: string): Promise<void> {
    throw new NotImplementedException();
  }
}
