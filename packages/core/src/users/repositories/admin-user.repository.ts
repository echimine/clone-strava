import { Inject, Injectable } from "@nestjs/common";
import { and, count, eq, gte, lt, sql, type SQL } from "drizzle-orm";
import type { AdminPremiumState, AdminUserPremiumFilter } from "@repo/contracts";
import { schema, type Database } from "@repo/db";
import { containsIgnoringAccents, DATABASE, offsetPage, parisDayRange } from "../../infrastructure/index.js";
import type { AdminUserFilter, AdminUserRow } from "../domain/admin-user.js";

const u = schema.user;
const p = schema.userProfile;
/** The athlete's `premium` row (one at most: the key is `(user_id, entitlement_id)`). */
const s = schema.userSubscription;

/**
 * The backoffice users list (ADR-038 §5): our own query, not Better Auth's `listUsers`, so search,
 * filters, sort and counts are one SQL statement.
 *
 * `users` owns this read. It also reads, read-only, Better Auth's `user` and `account`
 * (`auth`), Activity counts (`activities`) and the `premium` row of `user_subscription`
 * (`subscriptions`, whose `domain/premium-state.ts` rule `premiumState` below mirrors in SQL):
 * these joins only filter, sort and count.
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
    const state = premiumState(now);
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
        isPremium: sql<boolean>`coalesce(${isPremium(now)}, false)`,
        premiumState: sql<AdminPremiumState>`${state}`,
        premiumEndsAt: sql<string | null>`coalesce(${s.gracePeriodExpiresAt}, ${s.expiresAt})`,
      })
      .from(u)
      .leftJoin(p, eq(p.userId, u.id))
      .leftJoin(s, premiumRow)
      .where(where)
      // Accounts without an Activity come last in either order.
      .orderBy(sql`${sortColumn} ${direction} nulls last`, sql`${u.id} ${direction}`)
      .limit(limit)
      .offset(offset);
    const totalQuery = this.db
      .select({ total: count() })
      .from(u)
      .leftJoin(p, eq(p.userId, u.id))
      .leftJoin(s, premiumRow)
      .where(where);
    const [rows, [total]] = await Promise.all([rowsQuery, totalQuery]);
    return {
      rows: rows.map((row) => ({
        ...row,
        lastActivityAt: row.lastActivityAt === null ? null : new Date(row.lastActivityAt),
        premiumEndsAt: row.premiumEndsAt === null ? null : new Date(row.premiumEndsAt),
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
      filter.premium ? premiumFilter(filter.premium, now) : undefined,
      filter.method === "google" ? hasGoogle : undefined,
      filter.method === "email_code" ? sql`not ${hasGoogle}` : undefined,
      start ? gte(u.createdAt, start) : undefined,
      end ? lt(u.createdAt, end) : undefined,
    ];
  }
}

const premiumRow = and(eq(s.userId, u.id), eq(s.entitlementId, "premium"));

/**
 * `SubscriptionsService.isPremium`'s rule in SQL: active, and before its grace period's end or
 * expiry. Null without a row.
 */
function isPremium(now: Date): SQL {
  return sql`(${s.isActive} and coalesce(${s.gracePeriodExpiresAt}, ${s.expiresAt}, 'infinity'::timestamptz) > ${now})`;
}

/**
 * `premiumState` (`subscriptions/domain/premium-state.ts`) in SQL, same order: no row, expired,
 * promotional, grace period, billing issue, cancelled, trial, paying. Change both together.
 */
function premiumState(now: Date): SQL {
  return sql`(case
    when ${s.userId} is null then 'never'
    when not ${isPremium(now)} then 'expired'
    when ${s.store} = 'promotional' or ${s.periodType} = 'promotional' then 'promotional'
    when ${s.expiresAt} <= ${now} then 'grace_period'
    when ${s.billingIssueDetectedAt} is not null then 'billing_issue'
    when not ${s.willRenew} then 'cancelled'
    when ${s.periodType} = 'trial' then 'trial'
    else 'paying' end)`;
}

/** The list's Premium filter (ADR-038 §12): « Problème de paiement » takes the grace period in. */
function premiumFilter(filter: AdminUserPremiumFilter, now: Date): SQL {
  const states: AdminPremiumState[] = filter === "billing_issue" ? ["grace_period", "billing_issue"] : [filter];
  return sql`${premiumState(now)} in (${sql.join(
    states.map((state) => sql`${state}`),
    sql`, `,
  )})`;
}
