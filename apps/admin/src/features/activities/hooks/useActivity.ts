import { useQuery } from "@tanstack/react-query";
import { getActivity } from "@/features/activities/api";
import { activityKeys } from "@/features/activities/query-keys";

/** A single activity, for the detail page (ADR-013). */
export function useActivity(id: string) {
  return useQuery({
    queryKey: activityKeys.detail(id),
    queryFn: ({ signal }) => getActivity(id, signal),
  });
}
