import { Injectable } from "@nestjs/common";
import type { AdminPremiumState, PromotionalPremiumDuration } from "@repo/contracts";
import type { InstantRange } from "../infrastructure/index.js";
import {
  PremiumAdminStatsRepository,
  type PremiumNowCounts,
  type PremiumStartCounts,
} from "./repositories/premium-admin-stats.repository.js";
import { RevenuecatEventRepository, type PremiumEventRow } from "./repositories/revenuecat-event.repository.js";
import { UserSubscriptionRepository } from "./repositories/user-subscription.repository.js";
import { RevenueCatClient } from "./services/revenuecat-client.js";
import { SyncJobEnqueuer } from "./services/sync-job-enqueuer.js";
import {
  HandleRevenuecatWebhookUseCase,
  type RevenueCatWebhookDelivery,
} from "./use-cases/handle-revenuecat-webhook.use-case.js";
import { PromotionalPremiumUseCase } from "./use-cases/promotional-premium.use-case.js";
import { SyncSubscriptionUseCase } from "./use-cases/sync-subscription.use-case.js";
import { isPremium } from "./domain/is-premium.js";
import type { PremiumMirror } from "./domain/premium-mirror.js";
import { premiumState } from "./domain/premium-state.js";

/** The user sheet's Premium (ADR-038 §12), read in our tables only. */
export interface AdminPremium {
  state: AdminPremiumState;
  /** The `premium` row; null when the athlete never had one. */
  row: (PremiumMirror & { syncedAt: Date | null }) | null;
  /** RevenueCat events received for the athlete, newest first. */
  events: PremiumEventRow[];
}

/** Public facade of the `subscriptions` module (ADR-021 §1, layer 0). */
@Injectable()
export class SubscriptionsService {
  constructor(
    private readonly adminStats: PremiumAdminStatsRepository,
    private readonly userSubscriptions: UserSubscriptionRepository,
    private readonly revenuecatEvents: RevenuecatEventRepository,
    private readonly revenueCat: RevenueCatClient,
    private readonly syncJobs: SyncJobEnqueuer,
    private readonly handleRevenuecatWebhook: HandleRevenuecatWebhookUseCase,
    private readonly syncSubscription: SyncSubscriptionUseCase,
    private readonly promotionalPremium: PromotionalPremiumUseCase,
  ) {}

  // --- Backoffice (ADR-038 §12) ---

  /** RevenueCat's API v2 is configured: Premium can be synced, offered and taken back. */
  get revenueCatConfigured(): boolean {
    return this.revenueCat.configured;
  }

  /** The athlete as a customer in the RevenueCat dashboard; null without a project id. */
  revenueCatCustomerUrl(userId: string): string | null {
    return this.revenueCat.dashboardUrl(userId);
  }

  /** The user sheet's « Premium » section: state, the `premium` row, the RevenueCat events. */
  async getAdminPremium(userId: string, historyLimit: number, now = new Date()): Promise<AdminPremium> {
    const [row, events] = await Promise.all([
      this.userSubscriptions.findPremiumRow(userId),
      this.revenuecatEvents.listForUser(userId, historyLimit),
    ]);
    return { state: premiumState(row, now), row: row ?? null, events };
  }

  /** Promotional Premium active now (« Premium offerts actifs »), Sandbox left out. */
  countActivePromotionalPremium(now: Date, excludedUserIds: readonly string[]): Promise<number> {
    return this.adminStats.countPromotionalActiveAt(now, excludedUserIds);
  }

  /** « Resynchroniser »: queues `sync-subscription`; false when one is already waiting. */
  requestSync(userId: string, requestId?: string): Promise<boolean> {
    this.revenueCat.assertConfigured();
    return this.syncJobs.enqueue(userId, requestId);
  }

  /** « Offrir le Premium » for 1, 3, 6 or 12 months; offering again replaces the end. Returns it. */
  grantPromotionalPremium(userId: string, duration: PromotionalPremiumDuration, requestId?: string): Promise<Date> {
    return this.promotionalPremium.grant(userId, duration, requestId);
  }

  /** « Retirer le Premium offert », at once; never an App Store subscription. */
  revokePromotionalPremium(userId: string, requestId?: string): Promise<void> {
    return this.promotionalPremium.revoke(userId, requestId);
  }

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

  handleWebhook(delivery: RevenueCatWebhookDelivery, requestId?: string): Promise<void> {
    return this.handleRevenuecatWebhook.execute(delivery, requestId);
  }

  sync(userId: string): Promise<void> {
    return this.syncSubscription.execute(userId);
  }
}
