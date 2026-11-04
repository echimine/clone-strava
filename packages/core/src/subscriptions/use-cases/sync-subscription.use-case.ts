import { Injectable } from "@nestjs/common";
import { mirrorPremium, type PremiumMirror } from "../domain/premium-mirror.js";
import { RevenuecatEventRepository } from "../repositories/revenuecat-event.repository.js";
import { UserSubscriptionRepository } from "../repositories/user-subscription.repository.js";
import { RevenueCatClient } from "../services/revenuecat-client.js";

/**
 * `sync-subscription` job logic (ADR-014, ADR-011, ADR-038 §12): re-reads the customer and its
 * subscriptions from RevenueCat's API v2 (never v1, whose read creates the customer) and writes
 * the `premium` row as a mirror of the entitlement RevenueCat computes. The only writer of
 * `user_subscription`. Called by `apps/worker`'s processor, never enqueues itself.
 */
@Injectable()
export class SyncSubscriptionUseCase {
  constructor(
    private readonly userSubscriptions: UserSubscriptionRepository,
    private readonly revenuecatEvents: RevenuecatEventRepository,
    private readonly revenueCat: RevenueCatClient,
  ) {}

  async execute(userId: string, now = new Date()): Promise<void> {
    const entitlementId = this.revenueCat.premiumEntitlementId;
    const customer = await this.revenueCat.getCustomer(userId);
    const subscriptions = customer ? await this.revenueCat.listSubscriptions(userId) : [];
    const active = customer?.active_entitlements.find((entitlement) => entitlement.entitlement_id === entitlementId);
    const previous = await this.userSubscriptions.findPremiumRow(userId);

    const mirror = mirrorPremium({
      entitlementId,
      activeEntitlement: active ? { expiresAt: active.expires_at === null ? null : new Date(active.expires_at) } : null,
      subscriptions,
      previous: previous && toMirror(previous),
      now,
    });
    if (mirror) {
      await this.userSubscriptions.upsertPremium(userId, mirror, now);
    }
    await this.revenuecatEvents.markProcessed(userId, now);
  }
}

function toMirror(row: PremiumMirror): PremiumMirror {
  return {
    isActive: row.isActive,
    productId: row.productId,
    store: row.store,
    periodType: row.periodType,
    willRenew: row.willRenew,
    purchasedAt: row.purchasedAt,
    expiresAt: row.expiresAt,
    gracePeriodExpiresAt: row.gracePeriodExpiresAt,
    billingIssueDetectedAt: row.billingIssueDetectedAt,
    unsubscribeDetectedAt: row.unsubscribeDetectedAt,
    environment: row.environment,
  };
}
