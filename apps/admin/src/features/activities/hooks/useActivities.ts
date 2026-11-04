import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { listActivities, type ActivityListFilters } from "@/features/activities/api";
import { activityKeys } from "@/features/activities/query-keys";

/** A page of the Activities list, server-side filtered and paged (ADR-038 §2, §11). */
export function useActivities(filters: ActivityListFilters) {
  return useQuery({
    queryKey: activityKeys.list(filters),
    queryFn: ({ signal }) => listActivities(filters, signal),
    placeholderData: keepPreviousData,
  });
}
