"use client";

import { AuditEntryTable } from "@/features/audit/components/AuditEntryTable";
import { useAuditEntries } from "@/features/audit/hooks/useAuditEntries";
import { useListUrlState } from "@/lib/list-url-state";

/**
 * "Historique" (ADR-038 §3): the Journal entries whose athlete concerned is `subjectUserId`,
 * newest first, 25 per page by default. Made for the user sheet, which the page composes with
 * it (`app/(admin)/users/[id]/page.tsx`): its page lives in the URL as `historyPage`.
 */
export function AuditHistory({ subjectUserId }: { subjectUserId: string }) {
  const list = useListUrlState({ prefix: "history", defaultPageSize: 25 });
  const { data, isLoading, isPlaceholderData } = useAuditEntries({
    subjectUserId,
    page: list.page,
    pageSize: list.pageSize,
  });

  return (
    <AuditEntryTable
      data={data?.items ?? []}
      isLoading={isLoading}
      withSubject={false}
      pagination={{ list, total: data?.total ?? 0, itemLabel: "entrées", disabled: isPlaceholderData }}
    />
  );
}
