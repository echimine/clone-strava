import type { ActivityListFilters } from "@/features/activities/api";

/**
 * Hierarchical cache keys for the `activities` feature (ADR-013 §"Tables and filters", TanStack
 * Query query-keys guide).
 */
export const activityKeys = {
  all: ["activities"] as const,
  lists: () => [...activityKeys.all, "list"] as const,
  list: (filters: ActivityListFilters) => [...activityKeys.lists(), filters] as const,
  details: () => [...activityKeys.all, "detail"] as const,
  detail: (id: string) => [...activityKeys.details(), id] as const,
};

/**
 * The Journal's cache (`auditKeys.all` of the `audit` feature, which this feature may not
 * import): every admin action adds an entry, so each mutation invalidates it.
 */
export const journalKey = ["audit"] as const;
