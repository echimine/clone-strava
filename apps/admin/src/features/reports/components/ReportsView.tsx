"use client";

import { reportReasonSchema, reportTargetTypeSchema } from "@repo/contracts";
import { Tabs, TabsList, TabsTrigger } from "@repo/ui/components/tabs";
import { ReportCaseTable } from "@/features/reports/components/ReportCaseTable";
import { ReportFilters } from "@/features/reports/components/ReportFilters";
import { useReportCases } from "@/features/reports/hooks/useReportCases";
import { useListUrlState } from "@/lib/list-url-state";

/**
 * The moderation queue (ADR-038 §10): tabs « À traiter » and « Clos », one row per case, the case
 * open the longest first, then the most reported. Tab, filters and page live in the URL.
 */
export function ReportsView() {
  const list = useListUrlState();
  const state = list.get("state") === "closed" ? "closed" : "open";
  const targetType = reportTargetTypeSchema.safeParse(list.get("targetType"));
  const reason = reportReasonSchema.safeParse(list.get("reason"));
  const { data, isLoading, isPlaceholderData } = useReportCases({
    page: list.page,
    pageSize: list.pageSize,
    state,
    targetType: targetType.success ? targetType.data : undefined,
    reason: reason.success ? reason.data : undefined,
    from: list.get("from"),
    to: list.get("to"),
  });

  return (
    <div className="flex flex-col gap-4">
      <Tabs
        value={state}
        onValueChange={(value) => list.setFilters({ state: value === "closed" ? "closed" : undefined })}
      >
        <TabsList>
          <TabsTrigger value="open">À traiter</TabsTrigger>
          <TabsTrigger value="closed">Clos</TabsTrigger>
        </TabsList>
      </Tabs>
      <ReportFilters list={list} />
      <ReportCaseTable
        closed={state === "closed"}
        data={data?.items ?? []}
        isLoading={isLoading}
        pagination={{ list, total: data?.total ?? 0, itemLabel: "dossiers", disabled: isPlaceholderData }}
      />
    </div>
  );
}
