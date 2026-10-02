import { Inject, Injectable } from "@nestjs/common";
import { inArray } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE } from "../../infrastructure/index.js";

/** Read-only access to Better Auth's own `user` table (ADR-021 §6). */
@Injectable()
export class AuthUserRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  findPublicByIds(ids: string[]) {
    if (ids.length === 0) {
      return Promise.resolve([]);
    }
    return this.db
      .select({ id: schema.user.id, name: schema.user.name, image: schema.user.image })
      .from(schema.user)
      .where(inArray(schema.user.id, ids));
  }
}
