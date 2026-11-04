import type { AdminPremiumState, SubscriptionPeriodType, SubscriptionStore } from "@repo/contracts";
import { isPremium, type SubscriptionState } from "./is-premium.js";

/** The subset of the `premium` row the backoffice state needs. */
export interface PremiumRowState extends SubscriptionState {
  store: SubscriptionStore | null;
  periodType: SubscriptionPeriodType | null;
  willRenew: boolean;
  billingIssueDetectedAt: Date | null;
}

/**
 * The Premium state the backoffice shows (ADR-038 §12), from the `premium` row at `now`:
 *
 * 1. no row → `never`; a row that no longer gives Premium (`isPremium`) → `expired`;
 * 2. Promotional Premium (store or period `promotional`) → `promotional`;
 * 3. past its end but within Apple's grace period → `grace_period`;
 * 4. a payment failed → `billing_issue`;
 * 5. will not renew → `cancelled` (« Résilié jusqu'au … »);
 * 6. otherwise `trial` in a free trial, `paying` in any paid period.
 *
 * `AdminUserRepository` (users list filter) mirrors this rule in SQL: change both together.
 */
export function premiumState(row: PremiumRowState | undefined, now: Date): AdminPremiumState {
  if (!row) {
    return "never";
  }
  if (!isPremium(row, now)) {
    return "expired";
  }
  if (row.store === "promotional" || row.periodType === "promotional") {
    return "promotional";
  }
  if (row.expiresAt && row.expiresAt.getTime() <= now.getTime()) {
    return "grace_period";
  }
  if (row.billingIssueDetectedAt) {
    return "billing_issue";
  }
  if (!row.willRenew) {
    return "cancelled";
  }
  return row.periodType === "trial" ? "trial" : "paying";
}

/** The « Fin » of a row: the grace period's end when there is one, else the period's end. */
export function premiumEndsAt(row: Pick<SubscriptionState, "expiresAt" | "gracePeriodExpiresAt"> | undefined): Date | null {
  return row?.gracePeriodExpiresAt ?? row?.expiresAt ?? null;
}
