import { Inject, Injectable } from "@nestjs/common";
import { and, count, eq, ne } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { countsByDay, DATABASE, parisDay, withinRange, type InstantRange } from "../../infrastructure/index.js";

/** Backoffice dashboard reads (ADR-038 §15) over Better Auth's `user` table. */
@Injectable()
export class AuthAdminStatsRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  async findAdminIds(): Promise<string[]> {
    const rows = await this.db.select({ id: schema.user.id }).from(schema.user).where(eq(schema.user.role, "admin"));
    return rows.map((row) => row.id);
  }

  /** Accounts created per Paris day of `range`, Administrators left out (days without any are absent). */
  async countSignUpsPerParisDay(range: InstantRange): Promise<Map<string, number>> {
    const day = parisDay(schema.user.createdAt);
    const rows = await this.db
      .select({ day, total: count() })
      .from(schema.user)
      .where(and(withinRange(schema.user.createdAt, range), ne(schema.user.role, "admin")))
      .groupBy(day);
    return countsByDay(rows);
  }
}
