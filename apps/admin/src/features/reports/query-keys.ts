import type { ReportCaseListFilters } from "@/features/reports/api";

/** Hierarchical cache keys for the `reports` feature (the moderation queue). */
export const reportKeys = {
  all: ["reports"] as const,
  lists: () => [...reportKeys.all, "list"] as const,
  list: (filters: ReportCaseListFilters) => [...reportKeys.lists(), filters] as const,
  details: () => [...reportKeys.all, "detail"] as const,
  detail: (caseId: string) => [...reportKeys.details(), caseId] as const,
};

/**
 * Caches of other features this one may not import: the Journal (every action adds an entry),
 * the Activities and the users a Sanction changes, and the dashboard's open cases.
 */
export const foreignKeys = [["audit"], ["activities"], ["users"], ["dashboard"]] as const;
