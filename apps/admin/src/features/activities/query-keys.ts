import type { ActivityListFilters } from "@/features/activities/api";

/**
 * Hierarchical cache keys for the `activities` feature (ADR-013
 * §"Tables and filters", TanStack Query query-keys guide).
 */
export const activityKeys = {
  all: ["activities"] as const,
  lists: () => [...activityKeys.all, "list"] as const,
  list: (filters: ActivityListFilters) => [...activityKeys.lists(), filters] as const,
  details: () => [...activityKeys.all, "detail"] as const,
  detail: (id: string) => [...activityKeys.details(), id] as const,
};
