import { describe, expect, it } from "vitest";
import { premiumEndsAt, premiumState, type PremiumRowState } from "./premium-state.js";

const now = new Date("2026-11-04T12:00:00Z");
const later = new Date("2026-12-04T12:00:00Z");
const earlier = new Date("2026-10-04T12:00:00Z");

const paying: PremiumRowState = {
  isActive: true,
  expiresAt: later,
  gracePeriodExpiresAt: null,
  store: "app_store",
  periodType: "normal",
  willRenew: true,
  billingIssueDetectedAt: null,
};

describe("premiumState (ADR-038 §12)", () => {
  it("« Jamais abonné » without a row", () => {
    expect(premiumState(undefined, now)).toBe("never");
  });

  it("« Payant » for a paid period that renews, intro included", () => {
    expect(premiumState(paying, now)).toBe("paying");
    expect(premiumState({ ...paying, periodType: "intro" }, now)).toBe("paying");
  });

  it("« Essai » for a free trial that renews", () => {
    expect(premiumState({ ...paying, periodType: "trial" }, now)).toBe("trial");
  });

  it("« Premium offert » for the promotional store or period, even though it never renews", () => {
    const promotional = { ...paying, store: "promotional", periodType: "promotional", willRenew: false } as const;
    expect(premiumState(promotional, now)).toBe("promotional");
    expect(premiumState({ ...paying, store: null, periodType: "promotional", willRenew: false }, now)).toBe("promotional");
  });

  it("« Période de grâce » past its end within the grace period", () => {
    expect(
      premiumState({ ...paying, expiresAt: earlier, gracePeriodExpiresAt: later, billingIssueDetectedAt: earlier }, now),
    ).toBe("grace_period");
  });

  it("« Problème de paiement » while still in its period", () => {
    expect(premiumState({ ...paying, billingIssueDetectedAt: earlier }, now)).toBe("billing_issue");
  });

  it("« Résilié jusqu'au … » when it will not renew, a trial included", () => {
    expect(premiumState({ ...paying, willRenew: false }, now)).toBe("cancelled");
    expect(premiumState({ ...paying, periodType: "trial", willRenew: false }, now)).toBe("cancelled");
  });

  it("« Expiré » once it no longer gives Premium, whatever its source", () => {
    expect(premiumState({ ...paying, expiresAt: earlier }, now)).toBe("expired");
    expect(premiumState({ ...paying, isActive: false }, now)).toBe("expired");
    expect(premiumState({ ...paying, store: "promotional", periodType: "promotional", isActive: false }, now)).toBe(
      "expired",
    );
  });
});

describe("premiumEndsAt", () => {
  it("is the grace period's end when there is one, else the period's end", () => {
    expect(premiumEndsAt(undefined)).toBeNull();
    expect(premiumEndsAt(paying)).toEqual(later);
    expect(premiumEndsAt({ expiresAt: earlier, gracePeriodExpiresAt: later })).toEqual(later);
    expect(premiumEndsAt({ expiresAt: null, gracePeriodExpiresAt: null })).toBeNull();
  });
});
