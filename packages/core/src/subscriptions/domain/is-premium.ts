/** The subset of `user_subscription` (ADR-017) the premium rule needs. */
export interface SubscriptionState {
  isActive: boolean;
  expiresAt: Date | null;
  gracePeriodExpiresAt: Date | null;
}

/**
 * Premium status rule (ADR-021 §6 "pure ... premium status computation"):
 * active, and either not yet expired or still within its grace period.
 *
 * Pure and DB-free on purpose: `SubscriptionsService.isPremium` reads the
 * row, then delegates the decision here so it can be unit-tested without a
 * database and reused identically by every premium-gated endpoint.
 */
export function isPremium(subscription: SubscriptionState | undefined, now: Date): boolean {
  if (!subscription || !subscription.isActive) {
    return false;
  }
  const deadline = subscription.gracePeriodExpiresAt ?? subscription.expiresAt;
  if (!deadline) {
    // Active with no expiry (e.g. lifetime entitlement): treated as premium.
    return true;
  }
  return deadline.getTime() > now.getTime();
}
