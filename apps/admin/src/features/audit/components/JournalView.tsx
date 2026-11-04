"use client";

import { auditActionSchema } from "@repo/contracts";
import { AuditEntryTable } from "@/features/audit/components/AuditEntryTable";
import { JournalFilters } from "@/features/audit/components/JournalFilters";
import { useAuditEntries } from "@/features/audit/hooks/useAuditEntries";
import { useListUrlState } from "@/lib/list-url-state";

/** The Journal (ADR-038 §3): every admin action, newest first, its filters in the URL. */
export function JournalView() {
  const list = useListUrlState();
  const action = auditActionSchema.safeParse(list.get("action"));
  const subjectUserId = list.get("subjectUserId");
  const { data, isLoading, isPlaceholderData } = useAuditEntries({
    page: list.page,
    pageSize: list.pageSize,
    actorId: list.get("actorId"),
    action: action.success ? action.data : undefined,
    subjectUserId,
    from: list.get("from"),
    to: list.get("to"),
  });
  const subjectName = data?.items.find((entry) => entry.subject?.id === subjectUserId)?.subject?.displayName;

  return (
    <div className="flex flex-col gap-4">
      <JournalFilters list={list} subjectName={subjectName} />
      <AuditEntryTable
        data={data?.items ?? []}
        isLoading={isLoading}
        onFilterSubject={(subject) => list.setFilters({ subjectUserId: subject.id })}
        pagination={{ list, total: data?.total ?? 0, itemLabel: "entrées", disabled: isPlaceholderData }}
      />
    </div>
  );
}
