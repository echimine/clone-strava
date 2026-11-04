import { Injectable } from "@nestjs/common";
import type { PromotionalPremiumDuration } from "@repo/contracts";
import { promotionalPremiumEnd } from "../domain/promotional-premium.js";
import { RevenueCatClient } from "../services/revenuecat-client.js";
import { SyncJobEnqueuer } from "../services/sync-job-enqueuer.js";

/**
 * Promotional Premium (ADR-038 §12), offered and taken back through RevenueCat's API v2. Nothing
 * is written here: RevenueCat's webhook (`NON_RENEWING_PURCHASE` `PROMOTIONAL`, then
 * `CANCELLATION`/`EXPIRATION`) triggers `sync-subscription`, the only writer of
 * `user_subscription`. A sync is also queued at once, so the sheet does not wait for the webhook.
 */
@Injectable()
export class PromotionalPremiumUseCase {
  constructor(
    private readonly revenueCat: RevenueCatClient,
    private readonly syncJobs: SyncJobEnqueuer,
  ) {}

  /**
   * Offers Premium for `duration` from `now`. Offering again replaces the end date: the current
   * grant is revoked first (RevenueCat ignores a grant ending within 2 h of another). Returns
   * the end date.
   */
  async grant(userId: string, duration: PromotionalPremiumDuration, requestId?: string, now = new Date()): Promise<Date> {
    const expiresAt = promotionalPremiumEnd(now, duration);
    await this.revenueCat.revokePremium(userId);
    await this.revenueCat.grantPremium(userId, expiresAt);
    await this.syncJobs.enqueue(userId, requestId);
    return expiresAt;
  }

  /** Takes the Promotional Premium back at once; an App Store subscription is never touched. */
  async revoke(userId: string, requestId?: string): Promise<void> {
    await this.revenueCat.revokePremium(userId);
    await this.syncJobs.enqueue(userId, requestId);
  }
}
