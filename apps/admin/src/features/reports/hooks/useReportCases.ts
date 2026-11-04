import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { getReportCase, listReportCases, type ReportCaseListFilters } from "@/features/reports/api";
import { reportKeys } from "@/features/reports/query-keys";

/** A page of the moderation queue, server-side filtered and paged (ADR-038 §2, §10). */
export function useReportCases(filters: ReportCaseListFilters) {
  return useQuery({
    queryKey: reportKeys.list(filters),
    queryFn: ({ signal }) => listReportCases(filters, signal),
    placeholderData: keepPreviousData,
  });
}

/** One case as the backoffice opens it (ADR-038 §10). */
export function useReportCase(caseId: string) {
  return useQuery({
    queryKey: reportKeys.detail(caseId),
    queryFn: ({ signal }) => getReportCase(caseId, signal),
  });
}
