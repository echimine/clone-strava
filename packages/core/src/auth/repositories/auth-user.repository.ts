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

  /** Every Administrator's id and address (ADR-038 §10: the new report case e-mail). */
  findAdminRecipients(): Promise<{ userId: string; email: string }[]> {
    return this.db
      .select({ userId: schema.user.id, email: schema.user.email })
      .from(schema.user)
      .where(eq(schema.user.role, "admin"))
      .orderBy(asc(schema.user.id));
  }

  /** What the backoffice user sheet reads of an account (ADR-038 §5), with its linked providers. */
  async findAccount(userId: string) {
    const [row] = await this.db
      .select({
        id: schema.user.id,
        email: schema.user.email,
        name: schema.user.name,
        role: schema.user.role,
        banned: schema.user.banned,
        banReason: schema.user.banReason,
        banExpires: schema.user.banExpires,
        twoFactorEnabled: schema.user.twoFactorEnabled,
        createdAt: schema.user.createdAt,
      })
      .from(schema.user)
      .where(eq(schema.user.id, userId));
    if (!row) {
      return undefined;
    }
    const providers = await this.db
      .select({ providerId: schema.account.providerId })
      .from(schema.account)
      .where(eq(schema.account.userId, userId));
    return { ...row, providerIds: providers.map((provider) => provider.providerId) };
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
