import { describe, expect, it } from "vitest";
import { isPremium } from "./is-premium.js";

const now = new Date("2026-09-24T12:00:00Z");

describe("isPremium", () => {
  it("is false when there is no subscription row", () => {
    expect(isPremium(undefined, now)).toBe(false);
  });

  it("is false when the subscription is not active", () => {
    expect(
      isPremium({ isActive: false, expiresAt: null, gracePeriodExpiresAt: null }, now),
    ).toBe(false);
  });

  it("is true when active with no expiry", () => {
    expect(
      isPremium({ isActive: true, expiresAt: null, gracePeriodExpiresAt: null }, now),
    ).toBe(true);
  });

  it("is true when active and not yet expired", () => {
    expect(
      isPremium(
        {
          isActive: true,
          expiresAt: new Date("2026-10-01T00:00:00Z"),
          gracePeriodExpiresAt: null,
        },
        now,
      ),
    ).toBe(true);
  });

  it("is false when active but past expiry with no grace period", () => {
    expect(
      isPremium(
        {
          isActive: true,
          expiresAt: new Date("2026-09-01T00:00:00Z"),
          gracePeriodExpiresAt: null,
        },
        now,
      ),
    ).toBe(false);
  });

  it("is true when expired but still within the grace period", () => {
    expect(
      isPremium(
        {
          isActive: true,
          expiresAt: new Date("2026-09-01T00:00:00Z"),
          gracePeriodExpiresAt: new Date("2026-10-01T00:00:00Z"),
        },
        now,
      ),
    ).toBe(true);
  });

  it("is false once the grace period itself has passed", () => {
    expect(
      isPremium(
        {
          isActive: true,
          expiresAt: new Date("2026-09-01T00:00:00Z"),
          gracePeriodExpiresAt: new Date("2026-09-10T00:00:00Z"),
        },
        now,
      ),
    ).toBe(false);
  });
});
