import { Inject, Injectable } from "@nestjs/common";
import { and, eq, gt, isNull, or } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";

/** Reads the admin plugin's Ban columns of `user` (ADR-038 §6). */
@Injectable()
export class BanRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  /** Ids of the athletes whose Ban is active at `now`: `banned and (ban_expires is null or ban_expires > now)`. */
  async findActivelyBannedIds(now: Date): Promise<string[]> {
    const rows = await this.db
      .select({ id: schema.user.id })
      .from(schema.user)
      .where(
        and(eq(schema.user.banned, true), or(isNull(schema.user.banExpires), gt(schema.user.banExpires, now))),
      );
    return rows.map((row) => row.id);
  }
}
