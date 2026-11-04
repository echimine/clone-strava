import type { AdminTrend } from "@repo/contracts";

export type ChangeDirection = "up" | "down" | "flat";

/** How a Growth tile shows its change versus the previous period (ADR-038 §15). */
export interface Change {
  label: string;
  direction: ChangeDirection;
}

/**
 * The change in % versus the previous period of the same length, rounded. Without anything in
 * the previous period there is no percentage: "nouveau".
 */
export function describeChange({ value, previous }: AdminTrend): Change {
  if (value === previous) {
    return { label: "0 %", direction: "flat" };
  }
  if (previous === 0) {
    return { label: "nouveau", direction: "up" };
  }
  const percent = Math.round(((value - previous) / previous) * 100);
  if (percent === 0) {
    return { label: "0 %", direction: "flat" };
  }
  return percent > 0 ? { label: `+${percent} %`, direction: "up" } : { label: `−${-percent} %`, direction: "down" };
}
