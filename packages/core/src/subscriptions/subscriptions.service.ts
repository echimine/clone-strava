import { Injectable } from "@nestjs/common";
import { UserSubscriptionRepository } from "./repositories/user-subscription.repository.js";
import { HandleRevenuecatWebhookUseCase } from "./use-cases/handle-revenuecat-webhook.use-case.js";
import { SyncSubscriptionUseCase } from "./use-cases/sync-subscription.use-case.js";
import { isPremium } from "./domain/is-premium.js";

/** Public facade of the `subscriptions` module (ADR-021 §1, layer 0). */
@Injectable()
export class SubscriptionsService {
  constructor(
    private readonly userSubscriptions: UserSubscriptionRepository,
    private readonly handleRevenuecatWebhook: HandleRevenuecatWebhookUseCase,
    private readonly syncSubscription: SyncSubscriptionUseCase,
  ) {}

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

  handleWebhook(eventId: string, userId: string): Promise<void> {
    return this.handleRevenuecatWebhook.execute(eventId, userId);
  }

  sync(userId: string): Promise<void> {
    return this.syncSubscription.execute(userId);
  }
}
