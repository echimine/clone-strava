import { Injectable } from "@nestjs/common";
import { ADMIN_PREMIUM_HISTORY_LIMIT, type AdminUserPremium } from "@repo/contracts";
import { SubscriptionsService } from "@repo/core/subscriptions";

/** The user sheet's « Premium » section (ADR-038 §12): our tables only, never RevenueCat. */
@Injectable()
export class AdminPremiumAssembler {
  constructor(private readonly subscriptions: SubscriptionsService) {}

  async premium(userId: string): Promise<AdminUserPremium> {
    const { state, row, events } = await this.subscriptions.getAdminPremium(userId, ADMIN_PREMIUM_HISTORY_LIMIT);
    return {
      configured: this.subscriptions.revenueCatConfigured,
      state,
      detail: row && {
        productId: row.productId,
        store: row.store,
        periodType: row.periodType,
        purchasedAt: iso(row.purchasedAt),
        expiresAt: iso(row.expiresAt),
        gracePeriodExpiresAt: iso(row.gracePeriodExpiresAt),
        willRenew: row.willRenew,
        unsubscribeDetectedAt: iso(row.unsubscribeDetectedAt),
        billingIssueDetectedAt: iso(row.billingIssueDetectedAt),
        sandbox: row.environment === "sandbox",
        syncedAt: iso(row.syncedAt),
      },
      history: events.map((event) => ({
        ...event,
        occurredAt: event.occurredAt.toISOString(),
        expiresAt: iso(event.expiresAt),
      })),
      revenueCatUrl: this.subscriptions.revenueCatCustomerUrl(userId),
    };
  }
}

function iso(date: Date | null): string | null {
  return date?.toISOString() ?? null;
}
