import { Inject, Injectable } from "@nestjs/common";
import { and, eq, sql } from "drizzle-orm";
import { schema, type Database } from "@repo/db";
import { DATABASE, notByUsers, withinRange, type InstantRange } from "../../infrastructure/index.js";

/** Premium now (ADR-038 §15): subscriptions active at the given instant, as `isPremium` reads them. */
export interface PremiumNowCounts {
  /** Paying (`normal` or `intro` period). */
  payingActive: number;
  /** In their free trial. */
  trialsActive: number;
}

/** Premium starts over a period (ADR-038 §15), from the RevenueCat events received. */
export interface PremiumStartCounts {
  /** `INITIAL_PURCHASE` of a trial. */
  trialsStarted: number;
  /** `INITIAL_PURCHASE` of a paying period, or a trial converted (`RENEWAL` with `is_trial_conversion`). */
  newPaying: number;
}

/**
 * Backoffice dashboard counts (ADR-038 §15) over `user_subscription` and `revenuecat_event`,
 * `sandbox` left out. An event's fields are read from its stored payload, whether it is the
 * webhook body (`{ event: {...} }`) or the event itself.
 */
@Injectable()
export class PremiumAdminStatsRepository {
  constructor(@Inject(DATABASE) private readonly db: Database) {}

  async countActiveAt(now: Date, excludedUserIds: readonly string[]): Promise<PremiumNowCounts> {
    const subscription = schema.userSubscription;
    const [row] = await this.db
      .select({
        payingActive:
          sql<number>`count(*) filter (where ${subscription.periodType} in ('normal', 'intro'))`.mapWith(Number),
        trialsActive: sql<number>`count(*) filter (where ${subscription.periodType} = 'trial')`.mapWith(Number),
      })
      .from(subscription)
      .where(
        and(
          eq(subscription.entitlementId, "premium"),
          eq(subscription.isActive, true),
          // `isPremium`: not expired, or still within its grace period; no end at all is premium.
          sql`coalesce(${subscription.gracePeriodExpiresAt}, ${subscription.expiresAt}, 'infinity') > ${now}`,
          sql`${subscription.environment} is distinct from 'sandbox'`,
          notByUsers(subscription.userId, excludedUserIds),
        ),
      );
    return { payingActive: row?.payingActive ?? 0, trialsActive: row?.trialsActive ?? 0 };
  }

  async countStarts(range: InstantRange, excludedUserIds: readonly string[]): Promise<PremiumStartCounts> {
    const event = schema.revenuecatEvent;
    const field = (name: string) => sql`coalesce(${event.payload}->'event', ${event.payload})->>${name}`;
    const [row] = await this.db
      .select({
        trialsStarted:
          sql<number>`count(*) filter (where ${event.type} = 'INITIAL_PURCHASE' and ${field("period_type")} = 'TRIAL')`.mapWith(
            Number,
          ),
        newPaying: sql<number>`count(*) filter (where
          (${event.type} = 'INITIAL_PURCHASE' and ${field("period_type")} in ('NORMAL', 'INTRO'))
          or (${event.type} = 'RENEWAL' and ${field("is_trial_conversion")} = 'true'))`.mapWith(Number),
      })
      .from(event)
      .where(
        and(
          withinRange(event.receivedAt, range),
          sql`${field("environment")} is distinct from 'SANDBOX'`,
          notByUsers(event.userId, excludedUserIds),
        ),
      );
    return { trialsStarted: row?.trialsStarted ?? 0, newPaying: row?.newPaying ?? 0 };
  }
}
