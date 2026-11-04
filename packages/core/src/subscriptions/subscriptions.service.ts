import { Injectable } from "@nestjs/common";
import type { InstantRange } from "../infrastructure/index.js";
import {
  PremiumAdminStatsRepository,
  type PremiumNowCounts,
  type PremiumStartCounts,
} from "./repositories/premium-admin-stats.repository.js";
import { UserSubscriptionRepository } from "./repositories/user-subscription.repository.js";
import { HandleRevenuecatWebhookUseCase } from "./use-cases/handle-revenuecat-webhook.use-case.js";
import { SyncSubscriptionUseCase } from "./use-cases/sync-subscription.use-case.js";
import { isPremium } from "./domain/is-premium.js";

/** Public facade of the `subscriptions` module (ADR-021 §1, layer 0). */
@Injectable()
export class SubscriptionsService {
  constructor(
    private readonly adminStats: PremiumAdminStatsRepository,
    private readonly userSubscriptions: UserSubscriptionRepository,
    private readonly handleRevenuecatWebhook: HandleRevenuecatWebhookUseCase,
    private readonly syncSubscription: SyncSubscriptionUseCase,
  ) {}

  /** Backoffice dashboard (ADR-038 §15): paying and trial subscriptions active at `now`, Sandbox left out. */
  countActivePremium(now: Date, excludedUserIds: readonly string[]): Promise<PremiumNowCounts> {
    return this.adminStats.countActiveAt(now, excludedUserIds);
  }

  /** Backoffice dashboard (ADR-038 §15): trials started and new paying athletes in `range`. */
  countPremiumStarts(range: InstantRange, excludedUserIds: readonly string[]): Promise<PremiumStartCounts> {
    return this.adminStats.countStarts(range, excludedUserIds);
  }

  async isPremium(userId: string): Promise<boolean> {
    const row = await this.userSubscriptions.findPremiumRow(userId);
    return isPremium(
      row && {
        isActive: row.isActive,
        expiresAt: row.expiresAt,
        gracePeriodExpiresAt: row.gracePeriodExpiresAt,
      },
      new Date(),
    );
  }

  /**
   * The user sheet's Premium badge and the Ban dialog's warning (ADR-038 §5): Premium now, and
   * whether an App Store subscription renews (Apple keeps billing a banned athlete).
   */
  async getPremiumBilling(userId: string): Promise<{ active: boolean; billedByAppStore: boolean }> {
    const row = await this.userSubscriptions.findPremiumRow(userId);
    const active = isPremium(
      row && { isActive: row.isActive, expiresAt: row.expiresAt, gracePeriodExpiresAt: row.gracePeriodExpiresAt },
      new Date(),
    );
    return { active, billedByAppStore: active && row?.store === "app_store" && row.willRenew === true };
  }

  handleWebhook(eventId: string, userId: string): Promise<void> {
    return this.handleRevenuecatWebhook.execute(eventId, userId);
  }

  sync(userId: string): Promise<void> {
    return this.syncSubscription.execute(userId);
  }
}
