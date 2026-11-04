import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { listAuditEntries, type AuditEntryFilters } from "@/features/audit/api";
import { auditKeys } from "@/features/audit/query-keys";

/** A page of the Journal, server-side filtered and paged (ADR-038 §2, §3). */
export function useAuditEntries(filters: AuditEntryFilters) {
  return useQuery({
    queryKey: auditKeys.list(filters),
    queryFn: ({ signal }) => listAuditEntries(filters, signal),
    placeholderData: keepPreviousData,
  });
}
