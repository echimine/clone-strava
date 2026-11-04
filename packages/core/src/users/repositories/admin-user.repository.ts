import { Inject, Injectable } from "@nestjs/common";
import { and, count, eq, gte, lt, sql, type SQL } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { containsIgnoringAccents, DATABASE, offsetPage, parisDayRange } from "../../infrastructure/index.js";
import type { AdminUserFilter, AdminUserRow } from "../domain/admin-user.js";

const u = schema.user;
const p = schema.userProfile;

/**
 * The backoffice users list (ADR-038 §5): our own query, not Better Auth's `listUsers`, so search,
 * filters, sort and counts are one SQL statement.
 *
 * `users` owns this read. It also reads, read-only, Better Auth's `user` and `account`
 * (`auth`), Activity counts (`activities`) and the Premium rule over `user_subscription`
 * (`subscriptions`, same rule as `domain/is-premium.ts`): these joins only filter, sort and count.
 */
@Injectable()
export class AdminUserRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  async findPage(
    filter: AdminUserFilter,
    page: { page: number; pageSize: number },
    now: Date,
  ): Promise<{ rows: AdminUserRow[]; total: number }> {
    const where = and(...this.conditions(filter, now));
    const { limit, offset } = offsetPage(page);
    const lastActivityAt = sql<Date | null>`(select max(${schema.activity.startedAt}) from ${schema.activity} where ${schema.activity.userId} = ${u.id})`;
    const direction = filter.order === "asc" ? sql`asc` : sql`desc`;
    const sortColumn = filter.sort === "lastActivityAt" ? lastActivityAt : sql`${u.createdAt}`;

    const rowsQuery = this.db
      .select({
        id: u.id,
        email: u.email,
        name: u.name,
        role: u.role,
        createdAt: u.createdAt,
        banned: u.banned,
        banReason: u.banReason,
        banExpires: u.banExpires,
        providerIds: sql<string[]>`coalesce((select array_agg(${schema.account.providerId}) from ${schema.account} where ${schema.account.userId} = ${u.id}), '{}')`,
        activityCount: sql<number>`(select count(*) from ${schema.activity} where ${schema.activity.userId} = ${u.id})::int`,
        lastActivityAt: sql<string | null>`${lastActivityAt}`,
        isPremium: sql<boolean>`${isPremium(now)}`,
      })
      .from(u)
      .leftJoin(p, eq(p.userId, u.id))
      .where(where)
      // Accounts without an Activity come last in either order.
      .orderBy(sql`${sortColumn} ${direction} nulls last`, sql`${u.id} ${direction}`)
      .limit(limit)
      .offset(offset);
    const totalQuery = this.db.select({ total: count() }).from(u).leftJoin(p, eq(p.userId, u.id)).where(where);
    const [rows, [total]] = await Promise.all([rowsQuery, totalQuery]);
    return {
      rows: rows.map((row) => ({
        ...row,
        lastActivityAt: row.lastActivityAt === null ? null : new Date(row.lastActivityAt),
      })),
      total: total?.total ?? 0,
    };
  }

  private conditions(filter: AdminUserFilter, now: Date): (SQL | undefined)[] {
    const { start, end } = parisDayRange(filter);
    const hasGoogle = sql`exists (select 1 from ${schema.account} where ${schema.account.userId} = ${u.id} and ${schema.account.providerId} = 'google')`;
    const activeBan = sql`(${u.banned} and (${u.banExpires} is null or ${u.banExpires} > ${now}))`;
    return [
      filter.q ? containsIgnoringAccents([p.firstName, p.lastName, u.email], filter.q) : undefined,
      filter.role ? eq(u.role, filter.role) : undefined,
      filter.state === "active" ? sql`not ${activeBan}` : undefined,
      filter.state === "banned" ? sql`(${u.banned} and ${u.banExpires} is null)` : undefined,
      filter.state === "temporarily_banned" ? sql`(${u.banned} and ${u.banExpires} > ${now})` : undefined,
      filter.premium === "yes" ? isPremium(now) : undefined,
      filter.premium === "no" ? sql`not ${isPremium(now)}` : undefined,
      filter.method === "google" ? hasGoogle : undefined,
      filter.method === "email_code" ? sql`not ${hasGoogle}` : undefined,
      start ? gte(u.createdAt, start) : undefined,
      end ? lt(u.createdAt, end) : undefined,
    ];
  }
}

/** `SubscriptionsService.isPremium`'s rule in SQL: active, and before its grace period's end or expiry. */
function isPremium(now: Date): SQL {
  const s = schema.userSubscription;
  return sql`exists (select 1 from ${s} where ${s.userId} = ${u.id} and ${s.entitlementId} = 'premium' and ${s.isActive}
    and coalesce(${s.gracePeriodExpiresAt}, ${s.expiresAt}, 'infinity'::timestamptz) > ${now})`;
}
