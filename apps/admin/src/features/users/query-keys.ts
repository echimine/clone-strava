import type { UserListFilters } from "@/features/users/api";

/** Hierarchical cache keys for the `users` feature (TanStack Query query-keys guide). */
export const userKeys = {
  all: ["users"] as const,
  lists: () => [...userKeys.all, "list"] as const,
  list: (filters: UserListFilters) => [...userKeys.lists(), filters] as const,
  details: () => [...userKeys.all, "detail"] as const,
  detail: (id: string) => [...userKeys.details(), id] as const,
  sessions: (id: string) => [...userKeys.detail(id), "sessions"] as const,
  reports: (id: string) => [...userKeys.detail(id), "reports"] as const,
};

/**
 * The Journal's cache (`auditKeys.all` of the `audit` feature, which this feature may not
 * import): every admin action adds an entry, so each mutation invalidates it, the user sheet's
 * Historique included.
 */
export const journalKey = ["audit"] as const;
