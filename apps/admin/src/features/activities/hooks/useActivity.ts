import { useQuery } from "@tanstack/react-query";
import { getActivity } from "@/features/activities/api";
import { activityKeys } from "@/features/activities/query-keys";

/** One Activity as the backoffice opens it (ADR-038 §11). */
export function useActivity(id: string) {
  return useQuery({
    queryKey: activityKeys.detail(id),
    queryFn: ({ signal }) => getActivity(id, signal),
  });
}
