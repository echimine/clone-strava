import { PROMOTIONAL_PREMIUM_MONTHS, type PromotionalPremiumDuration } from "@repo/contracts";

/**
 * The end of a Promotional Premium offered at `now` for `duration` (ADR-038 §12): that many
 * calendar months later, at the same time; a day the month lacks (the 31st) falls back to the
 * month's last day.
 */
export function promotionalPremiumEnd(now: Date, duration: PromotionalPremiumDuration): Date {
  const result = new Date(now);
  const day = result.getUTCDate();
  result.setUTCDate(1);
  result.setUTCMonth(result.getUTCMonth() + PROMOTIONAL_PREMIUM_MONTHS[duration]);
  const lastDay = new Date(Date.UTC(result.getUTCFullYear(), result.getUTCMonth() + 1, 0)).getUTCDate();
  result.setUTCDate(Math.min(day, lastDay));
  return result;
}
