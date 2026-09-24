"use client";

import { Button } from "@repo/ui/components/button";
import { useRouter, useSearchParams } from "next/navigation";
import { ActivityTable } from "@/features/activities/components/ActivityTable";
import { useActivities } from "@/features/activities/hooks/useActivities";

const DEFAULT_LIMIT = 20;

/**
 * Assembles the activities feature (ADR-013 reference feature): pagination
 * state lives in the URL search params so a filtered page can be shared or
 * reloaded.
 */
export function ActivitiesView() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const page = Number(searchParams.get("page") ?? "1");
  const limit = Number(searchParams.get("limit") ?? String(DEFAULT_LIMIT));

  const { data, isLoading, isPlaceholderData } = useActivities({ page, limit });

  function goToPage(nextPage: number) {
    const params = new URLSearchParams(searchParams);
    params.set("page", String(nextPage));
    router.push(`/activities?${params.toString()}`);
  }

  const total = data?.total ?? 0;
  const hasNextPage = data ? page * limit < total : false;

  return (
    <div className="flex flex-col gap-4">
      <ActivityTable activities={data?.items ?? []} isLoading={isLoading} />
      <div className="flex items-center justify-between">
        <p className="text-sm text-muted-foreground">
          {total > 0 ? `${total} activité${total > 1 ? "s" : ""}` : ""}
        </p>
        <div className="flex gap-2">
          <Button
            variant="outline"
            size="sm"
            disabled={page <= 1}
            onClick={() => goToPage(page - 1)}
          >
            Précédent
          </Button>
          <Button
            variant="outline"
            size="sm"
            disabled={!hasNextPage || isPlaceholderData}
            onClick={() => goToPage(page + 1)}
          >
            Suivant
          </Button>
        </div>
      </div>
    </div>
  );
}
