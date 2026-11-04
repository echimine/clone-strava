import type { AuditEntryFilters } from "@/features/audit/api";

/**
 * Cache keys of the `audit` feature. Any admin action adds an entry: a Sanction's mutation
 * invalidates `auditKeys.all` so the Journal and the Historique show it.
 */
export const auditKeys = {
  all: ["audit"] as const,
  lists: () => [...auditKeys.all, "list"] as const,
  list: (filters: AuditEntryFilters) => [...auditKeys.lists(), filters] as const,
  actors: () => [...auditKeys.all, "actors"] as const,
};
