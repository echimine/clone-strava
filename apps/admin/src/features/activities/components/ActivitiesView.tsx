"use client";

import { activitySourceSchema, processingStatusSchema, visibilitySchema } from "@repo/contracts";
import { ActivityFilters } from "@/features/activities/components/ActivityFilters";
import { ActivityTable } from "@/features/activities/components/ActivityTable";
import { useActivities } from "@/features/activities/hooks/useActivities";
import { useListUrlState } from "@/lib/list-url-state";

/**
 * The backoffice Activities list (ADR-038 §11): every Activity, private ones included, newest
 * created first, its filters and page in the URL (a user sheet links here with `userId`).
 */
export function ActivitiesView() {
  const list = useListUrlState();
  const status = processingStatusSchema.safeParse(list.get("status"));
  const source = activitySourceSchema.safeParse(list.get("source"));
  const visibility = visibilitySchema.safeParse(list.get("visibility"));
  const userId = list.get("userId");
  const { data, isLoading, isPlaceholderData } = useActivities({
    page: list.page,
    pageSize: list.pageSize,
    q: list.get("q"),
    status: status.success ? status.data : undefined,
    source: source.success ? source.data : undefined,
    sportTypeCode: list.get("sportTypeCode"),
    visibility: visibility.success ? visibility.data : undefined,
    userId,
    from: list.get("from"),
    to: list.get("to"),
  });
  const athleteName = data?.items.find((item) => item.athlete.id === userId)?.athlete.displayName;

  return (
    <div className="flex flex-col gap-4">
      <ActivityFilters list={list} athleteName={athleteName} />
      <ActivityTable
        data={data?.items ?? []}
        isLoading={isLoading}
        pagination={{ list, total: data?.total ?? 0, itemLabel: "activités", disabled: isPlaceholderData }}
      />
    </div>
  );
}
