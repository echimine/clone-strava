/** Injection token of {@link RevenueCatOptions}, set by `RevenueCatModule.forRoot`. */
export const REVENUECAT_OPTIONS = Symbol("REVENUECAT_OPTIONS");

/**
 * RevenueCat's REST API v2 (ADR-038 §12). Premium can be synced, offered and taken back only
 * with all three settings; without them it is read-only (« RevenueCat non configuré »).
 */
export interface RevenueCatOptions {
  /** Secret v2 key (`sk_…`), API and worker only. */
  apiKey?: string;
  projectId?: string;
  /** RevenueCat's id of the `premium` entitlement (`entl…`). */
  premiumEntitlementId?: string;
  /** Tests answer in RevenueCat's place; defaults to the global `fetch`. */
  fetch?: typeof fetch;
}
