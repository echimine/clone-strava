import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { listActivities, type ActivityListFilters } from "@/features/activities/api";
import { activityKeys } from "@/features/activities/query-keys";

/** Server-side paginated activities list (ADR-013 §"Tables and filters"). */
export function useActivities(filters: ActivityListFilters) {
  return useQuery({
    queryKey: activityKeys.list(filters),
    queryFn: ({ signal }) => listActivities(filters, signal),
    placeholderData: keepPreviousData,
  });
}
