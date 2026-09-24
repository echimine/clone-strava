"use client";

import { Card, CardContent, CardHeader, CardTitle } from "@repo/ui/components/card";
import { Skeleton } from "@repo/ui/components/skeleton";
import dynamic from "next/dynamic";
import { useActivity } from "@/features/activities/hooks/useActivity";

// Client-only: mapbox-gl reads `window` at import time (ADR-012 §"Map").
const MapView = dynamic(() => import("@/components/MapView").then((mod) => mod.MapView), {
  ssr: false,
  loading: () => <Skeleton className="h-64 w-full" />,
});

export function ActivityDetailView({ id }: { id: string }) {
  const { data: activity, isLoading } = useActivity(id);

  if (isLoading) {
    return <Skeleton className="h-64 w-full" />;
  }

  if (!activity) {
    return <p className="text-sm text-muted-foreground">Activité introuvable.</p>;
  }

  return (
    <div className="flex flex-col gap-4">
      <Card>
        <CardHeader>
          <CardTitle>{activity.sportTypeCode}</CardTitle>
        </CardHeader>
        <CardContent className="grid gap-2 text-sm">
          <p>
            <span className="text-muted-foreground">Statut : </span>
            {activity.processingStatus}
          </p>
          <p>
            <span className="text-muted-foreground">Visibilité : </span>
            {activity.visibility}
          </p>
        </CardContent>
      </Card>
      <MapView className="h-96 w-full rounded-md" />
    </div>
  );
}
