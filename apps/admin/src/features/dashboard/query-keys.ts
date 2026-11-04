import type { AdminStatsPeriod } from "@repo/contracts";

/** Cache keys of the `dashboard` feature. */
export const dashboardKeys = {
  all: ["dashboard"] as const,
  todo: () => [...dashboardKeys.all, "todo"] as const,
  growth: (period: AdminStatsPeriod) => [...dashboardKeys.all, "growth", period] as const,
};
