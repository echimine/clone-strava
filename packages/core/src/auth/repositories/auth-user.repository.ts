import { Inject, Injectable } from "@nestjs/common";
import { and, asc, eq, gt, inArray, isNotNull } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";

/** Read-only access to Better Auth's own `user` and `account` tables (ADR-021 §6). */
@Injectable()
export class AuthUserRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  findPublicByIds(ids: string[]) {
    if (ids.length === 0) {
      return Promise.resolve([]);
    }
    return this.db
      .select({ id: schema.user.id, name: schema.user.name })
      .from(schema.user)
      .where(inArray(schema.user.id, ids));
  }

  /**
   * Accounts linked to Google that have a `user.image`, by id after `afterId` (keyset page): the
   * Google photo backfill (ADR-037 §2).
   */
  findGoogleAccountImages(afterId: string | null, limit: number) {
    return this.db
      .selectDistinct({ id: schema.user.id, image: schema.user.image })
      .from(schema.user)
      .innerJoin(schema.account, eq(schema.account.userId, schema.user.id))
      .where(
        and(
          eq(schema.account.providerId, "google"),
          isNotNull(schema.user.image),
          afterId === null ? undefined : gt(schema.user.id, afterId),
        ),
      )
      .orderBy(asc(schema.user.id))
      .limit(limit);
  }
}
