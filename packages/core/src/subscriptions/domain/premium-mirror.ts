import type {
  RevenueCatSubscription,
  SubscriptionEnvironment,
  SubscriptionPeriodType,
  SubscriptionStore,
} from "@repo/contracts";

/** What `sync-subscription` writes on the `premium` row of `user_subscription`. */
export interface PremiumMirror {
  isActive: boolean;
  productId: string | null;
  store: SubscriptionStore | null;
  periodType: SubscriptionPeriodType | null;
  willRenew: boolean;
  purchasedAt: Date | null;
  expiresAt: Date | null;
  gracePeriodExpiresAt: Date | null;
  billingIssueDetectedAt: Date | null;
  unsubscribeDetectedAt: Date | null;
  environment: SubscriptionEnvironment | null;
}

export interface PremiumMirrorInput {
  /** RevenueCat's id of the `premium` entitlement (`entl…`). */
  entitlementId: string;
  /** The entitlement among the customer's active ones; null when inactive or no customer. */
  activeEntitlement: { expiresAt: Date | null } | null;
  /** Every subscription of the customer, Promotional Premium grants included. */
  subscriptions: readonly RevenueCatSubscription[];
  /** The row as it is now, to keep when a billing issue or an unsubscription was first seen. */
  previous: PremiumMirror | undefined;
  now: Date;
}

/** Renewal statuses that bill another period. */
const RENEWING = new Set(["will_renew", "will_change_product", "has_already_renewed"]);
const BILLING_ISSUE = new Set(["in_grace_period", "in_billing_retry"]);

/**
 * The `premium` row as RevenueCat computes the entitlement (ADR-038 §12): active or not and its
 * end come from the customer's active entitlement; the details come from its source, the
 * subscription giving the entitlement that ends last (an App Store subscription or a
 * Promotional Premium grant). Returns null when there is nothing to write: no row yet and
 * nothing at RevenueCat.
 */
export function mirrorPremium(input: PremiumMirrorInput): PremiumMirror | null {
  const { activeEntitlement, previous, now } = input;
  const sources = input.subscriptions.filter((subscription) => subscription.entitlements.includes(input.entitlementId));
  const source =
    latestEnding(activeEntitlement ? sources.filter((subscription) => subscription.gives_access) : []) ??
    latestEnding(sources);

  if (!source) {
    if (activeEntitlement) {
      return { ...emptyMirror(), ...previous, isActive: true, expiresAt: activeEntitlement.expiresAt };
    }
    return previous ? { ...previous, isActive: false } : null;
  }

  const store = toStore(source.store);
  const promotional = store === "promotional";
  const willRenew = !promotional && RENEWING.has(source.auto_renewal_status);
  const periodEnd = toDate(source.current_period_ends_at);
  const inGrace = activeEntitlement !== null && source.status === "in_grace_period";
  return {
    isActive: activeEntitlement !== null,
    productId: source.product_id,
    store,
    periodType: promotional ? "promotional" : source.status === "trialing" ? "trial" : "normal",
    willRenew,
    purchasedAt: new Date(source.starts_at),
    expiresAt: activeEntitlement ? (inGrace ? periodEnd : activeEntitlement.expiresAt) : toDate(endOf(source)),
    gracePeriodExpiresAt: inGrace ? activeEntitlement.expiresAt : null,
    billingIssueDetectedAt: BILLING_ISSUE.has(source.status) ? (previous?.billingIssueDetectedAt ?? now) : null,
    unsubscribeDetectedAt: !promotional && !willRenew ? (previous?.unsubscribeDetectedAt ?? now) : null,
    environment: toEnvironment(source.environment),
  };
}

function emptyMirror(): PremiumMirror {
  return {
    isActive: false,
    productId: null,
    store: null,
    periodType: null,
    willRenew: false,
    purchasedAt: null,
    expiresAt: null,
    gracePeriodExpiresAt: null,
    billingIssueDetectedAt: null,
    unsubscribeDetectedAt: null,
    environment: null,
  };
}

/** The end of the latest billing period; null = paused until an indefinite date. */
function endOf(subscription: RevenueCatSubscription): number | null {
  return subscription.ends_at ?? subscription.current_period_ends_at;
}

function latestEnding(subscriptions: readonly RevenueCatSubscription[]): RevenueCatSubscription | undefined {
  const rank = (subscription: RevenueCatSubscription) => endOf(subscription) ?? Number.POSITIVE_INFINITY;
  return subscriptions.reduce<RevenueCatSubscription | undefined>(
    (latest, subscription) => (!latest || rank(subscription) > rank(latest) ? subscription : latest),
    undefined,
  );
}

function toDate(ms: number | null): Date | null {
  return ms === null ? null : new Date(ms);
}

function toStore(store: string): SubscriptionStore | null {
  if (store === "app_store" || store === "mac_app_store") {
    return "app_store";
  }
  return store === "promotional" ? "promotional" : null;
}

function toEnvironment(environment: string | null | undefined): SubscriptionEnvironment | null {
  return environment === "sandbox" || environment === "production" ? environment : null;
}
