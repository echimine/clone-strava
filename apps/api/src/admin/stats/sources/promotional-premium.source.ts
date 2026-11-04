import { Injectable } from "@nestjs/common";
import { SubscriptionsService } from "@repo/core/subscriptions";

/**
 * Promotional Premium ("Premium offerts actifs") for the "Croissance" band (ADR-038 §12, §15):
 * the `premium` rows granted by an Administrator that give Premium at `now`, Administrators and
 * Sandbox left out.
 */
@Injectable()
export class PromotionalPremiumSource {
  constructor(private readonly subscriptions: SubscriptionsService) {}

  countActive(now: Date, excludedUserIds: readonly string[]): Promise<number> {
    return this.subscriptions.countActivePromotionalPremium(now, excludedUserIds);
  }
}
