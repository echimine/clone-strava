"use client";

import { reportReasonSchema, reportTargetTypeSchema } from "@repo/contracts";
import { Input } from "@repo/ui/components/input";
import { Label } from "@repo/ui/components/label";
import { NativeSelect, NativeSelectOption } from "@repo/ui/components/native-select";
import { reportReasonLabels, reportTargetLabels } from "@/features/reports/lib/labels";
import type { ListUrlState } from "@/lib/list-url-state";

/** The queue's filters (ADR-038 §10): target type, reason, opening period. All in the URL. */
export function ReportFilters({ list }: { list: ListUrlState }) {
  return (
    <div className="flex flex-wrap items-end gap-4">
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="reports-type">Type</Label>
        <NativeSelect
          id="reports-type"
          value={list.get("targetType") ?? ""}
          onChange={(event) => list.setFilters({ targetType: event.target.value })}
        >
          <NativeSelectOption value="">Tous</NativeSelectOption>
          {reportTargetTypeSchema.options.map((type) => (
            <NativeSelectOption key={type} value={type}>
              {reportTargetLabels[type]}
            </NativeSelectOption>
          ))}
        </NativeSelect>
      </div>
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="reports-reason">Motif</Label>
        <NativeSelect
          id="reports-reason"
          value={list.get("reason") ?? ""}
          onChange={(event) => list.setFilters({ reason: event.target.value })}
        >
          <NativeSelectOption value="">Tous</NativeSelectOption>
          {reportReasonSchema.options.map((reason) => (
            <NativeSelectOption key={reason} value={reason}>
              {reportReasonLabels[reason]}
            </NativeSelectOption>
          ))}
        </NativeSelect>
      </div>
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="reports-from">Ouvert du</Label>
        <Input
          id="reports-from"
          type="date"
          value={list.get("from") ?? ""}
          max={list.get("to")}
          onChange={(event) => list.setFilters({ from: event.target.value })}
        />
      </div>
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="reports-to">au</Label>
        <Input
          id="reports-to"
          type="date"
          value={list.get("to") ?? ""}
          min={list.get("from")}
          onChange={(event) => list.setFilters({ to: event.target.value })}
        />
      </div>
    </div>
  );
}
