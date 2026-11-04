import { describe, expect, it } from "vitest";
import type { RevenueCatSubscription } from "@repo/contracts";
import { mirrorPremium, type PremiumMirror } from "./premium-mirror.js";

const ENTITLEMENT = "entl_premium";
const now = new Date("2026-11-04T12:00:00Z");
const day = 24 * 3600 * 1000;
const at = (days: number) => now.getTime() + days * day;

function subscription(overrides: Partial<RevenueCatSubscription> = {}): RevenueCatSubscription {
  return {
    id: "sub_1",
    product_id: "prod_monthly",
    starts_at: at(-40),
    current_period_ends_at: at(20),
    ends_at: at(20),
    gives_access: true,
    auto_renewal_status: "will_renew",
    status: "active",
    store: "app_store",
    environment: "production",
    entitlements: [ENTITLEMENT],
    ...overrides,
  };
}

const promotionalGrant = (endsInDays: number) =>
  subscription({
    id: "sub_promo",
    product_id: null,
    store: "promotional",
    starts_at: at(-1),
    current_period_ends_at: at(endsInDays),
    ends_at: at(endsInDays),
    auto_renewal_status: "will_not_renew",
  });

describe("mirrorPremium (ADR-038 §12)", () => {
  it("mirrors a renewing App Store subscription", () => {
    expect(
      mirrorPremium({
        entitlementId: ENTITLEMENT,
        activeEntitlement: { expiresAt: new Date(at(20)) },
        subscriptions: [subscription()],
        previous: undefined,
        now,
      }),
    ).toEqual({
      isActive: true,
      productId: "prod_monthly",
      store: "app_store",
      periodType: "normal",
      willRenew: true,
      purchasedAt: new Date(at(-40)),
      expiresAt: new Date(at(20)),
      gracePeriodExpiresAt: null,
      billingIssueDetectedAt: null,
      unsubscribeDetectedAt: null,
      environment: "production",
    } satisfies PremiumMirror);
  });

  it("a trial is `trial`; a cancelled one notes when the unsubscription was first seen", () => {
    const trial = mirrorPremium({
      entitlementId: ENTITLEMENT,
      activeEntitlement: { expiresAt: new Date(at(5)) },
      subscriptions: [subscription({ status: "trialing", auto_renewal_status: "will_not_renew", environment: "sandbox" })],
      previous: undefined,
      now,
    });
    expect(trial).toMatchObject({ periodType: "trial", willRenew: false, unsubscribeDetectedAt: now, environment: "sandbox" });
    const firstSeen = new Date(at(-2));
    expect(
      mirrorPremium({
        entitlementId: ENTITLEMENT,
        activeEntitlement: { expiresAt: new Date(at(5)) },
        subscriptions: [subscription({ auto_renewal_status: "will_not_renew" })],
        previous: { ...trial!, unsubscribeDetectedAt: firstSeen },
        now,
      }),
    ).toMatchObject({ unsubscribeDetectedAt: firstSeen });
  });

  it("the source is the one that ends last: a Promotional Premium beyond the App Store period", () => {
    const row = mirrorPremium({
      entitlementId: ENTITLEMENT,
      activeEntitlement: { expiresAt: new Date(at(90)) },
      subscriptions: [subscription(), promotionalGrant(90)],
      previous: undefined,
      now,
    });
    expect(row).toMatchObject({
      isActive: true,
      productId: null,
      store: "promotional",
      periodType: "promotional",
      willRenew: false,
      unsubscribeDetectedAt: null,
      expiresAt: new Date(at(90)),
    });
  });

  it("the App Store subscription stays the source when it ends after the Promotional Premium", () => {
    const row = mirrorPremium({
      entitlementId: ENTITLEMENT,
      activeEntitlement: { expiresAt: new Date(at(20)) },
      subscriptions: [subscription(), promotionalGrant(10)],
      previous: undefined,
      now,
    });
    expect(row).toMatchObject({ store: "app_store", periodType: "normal", expiresAt: new Date(at(20)) });
  });

  it("in the grace period: the period's end passed, the entitlement runs to the grace period's end", () => {
    const row = mirrorPremium({
      entitlementId: ENTITLEMENT,
      activeEntitlement: { expiresAt: new Date(at(6)) },
      subscriptions: [subscription({ status: "in_grace_period", current_period_ends_at: at(-1), ends_at: at(-1) })],
      previous: undefined,
      now,
    });
    expect(row).toMatchObject({
      isActive: true,
      expiresAt: new Date(at(-1)),
      gracePeriodExpiresAt: new Date(at(6)),
      billingIssueDetectedAt: now,
    });
  });

  it("no active entitlement: inactive, details from the last source; subscriptions of other entitlements ignored", () => {
    const row = mirrorPremium({
      entitlementId: ENTITLEMENT,
      activeEntitlement: null,
      subscriptions: [
        subscription({ status: "expired", gives_access: false, ends_at: at(-3), current_period_ends_at: at(-3) }),
        subscription({ id: "other", entitlements: ["entl_other"], ends_at: at(100) }),
      ],
      previous: undefined,
      now,
    });
    expect(row).toMatchObject({ isActive: false, store: "app_store", expiresAt: new Date(at(-3)) });
  });

  it("nothing at RevenueCat: no row to write, or the existing row turned inactive", () => {
    const input = { entitlementId: ENTITLEMENT, activeEntitlement: null, subscriptions: [], now };
    expect(mirrorPremium({ ...input, previous: undefined })).toBeNull();
    const previous = mirrorPremium({
      ...input,
      activeEntitlement: { expiresAt: new Date(at(30)) },
      subscriptions: [promotionalGrant(30)],
      previous: undefined,
    })!;
    expect(mirrorPremium({ ...input, previous })).toEqual({ ...previous, isActive: false });
  });
});
