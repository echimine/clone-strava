import { keepPreviousData, useQuery } from "@tanstack/react-query";
import type { AdminStatsPeriod } from "@repo/contracts";
import { getGrowthStats } from "@/features/dashboard/api";
import { dashboardKeys } from "@/features/dashboard/query-keys";

/** "Croissance" over `period` (ADR-038 §15); the shown figures stay while the next period loads. */
export function useGrowthStats(period: AdminStatsPeriod) {
  return useQuery({
    queryKey: dashboardKeys.growth(period),
    queryFn: ({ signal }) => getGrowthStats(period, signal),
    placeholderData: keepPreviousData,
  });
}
