"use client";

import type { AdminActivityDetail } from "@repo/contracts";
import { Badge } from "@repo/ui/components/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@repo/ui/components/card";
import { Skeleton } from "@repo/ui/components/skeleton";
import dynamic from "next/dynamic";
import Link from "next/link";
import type { ReactNode } from "react";
import { ActivityActions } from "@/features/activities/components/ActivityActions";
import {
  ActivityCommentsSection,
  ActivityExtrasSection,
  ActivityMediaSection,
} from "@/features/activities/components/ActivityContent";
import { useActivity } from "@/features/activities/hooks/useActivity";
import { useActivityActions } from "@/features/activities/hooks/useActivityActions";
import {
  formatDateTime,
  formatDistance,
  formatDuration,
  sourceLabels,
  sportLabel,
  statusLabels,
  statusVariants,
  visibilityLabels,
} from "@/features/activities/lib/labels";

// Client-only: mapbox-gl reads `window` at import time (ADR-012 §"Map").
const MapView = dynamic(() => import("@/components/MapView").then((mod) => mod.MapView), {
  ssr: false,
  loading: () => <Skeleton className="h-96 w-full" />,
});

function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="flex flex-col">
      <dt className="text-muted-foreground">{label}</dt>
      <dd>{children}</dd>
    </div>
  );
}

function Overview({ activity }: { activity: AdminActivityDetail }) {
  const stats = activity.stats;
  return (
    <Card>
      <CardHeader>
        <CardTitle>Valeurs officielles</CardTitle>
      </CardHeader>
      <CardContent>
        <dl className="grid grid-cols-2 gap-4 text-sm md:grid-cols-4">
          <Field label="Sport">{sportLabel(activity.sportTypeCode)}</Field>
          <Field label="Distance">{formatDistance(stats?.distanceM ?? null)}</Field>
          <Field label="Temps en mouvement">{formatDuration(stats?.movingTimeS ?? null)}</Field>
          <Field label="Temps écoulé">{formatDuration(stats?.elapsedTimeS ?? null)}</Field>
          <Field label="D+">{stats?.elevationGainM == null ? "—" : `${Math.round(stats.elevationGainM)} m`}</Field>
          <Field label="Début">{formatDateTime(activity.startedAt)}</Field>
          <Field label="Fin">{formatDateTime(activity.endedAt)}</Field>
          <Field label="Lieu">{activity.locationName ?? "—"}</Field>
          <Field label="Source">{sourceLabels[activity.source]}</Field>
          <Field label="Visibilité">{visibilityLabels[activity.visibility]}</Field>
          <Field label="Créée le">{formatDateTime(activity.createdAt)}</Field>
          <Field label="Traitée le">{activity.processedAt ? formatDateTime(activity.processedAt) : "—"}</Field>
          <Field label="Tentatives de traitement">{activity.processingAttempts}</Field>
          {activity.processingError ? (
            <Field label="Erreur de traitement">
              <code className="text-destructive">{activity.processingError}</code>
            </Field>
          ) : null}
        </dl>
        {activity.description ? <p className="mt-4 whitespace-pre-wrap text-sm">{activity.description}</p> : null}
      </CardContent>
    </Card>
  );
}

/**
 * An Activity as the backoffice opens it (ADR-038 §11): official values and status, the public
 * trace only, Media, comments, kudos, import and Segment efforts, with « Retraiter » and the
 * Sanctions.
 */
export function ActivityDetailView({ id }: { id: string }) {
  const { data: activity, isLoading } = useActivity(id);
  const actions = useActivityActions(id);

  if (isLoading) {
    return <Skeleton className="h-64 w-full" />;
  }
  if (!activity) {
    return <p className="text-sm text-muted-foreground">Activité introuvable.</p>;
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div className="flex flex-col gap-1">
          <h2 className="text-xl font-semibold">{activity.title}</h2>
          <p className="flex items-center gap-2 text-sm text-muted-foreground">
            <Link href={`/users/${activity.athlete.id}`} className="text-foreground underline-offset-4 hover:underline">
              {activity.athlete.displayName || activity.athlete.id.slice(0, 8)}
            </Link>
            <Badge variant={statusVariants[activity.processingStatus]}>{statusLabels[activity.processingStatus]}</Badge>
          </p>
        </div>
        <ActivityActions activity={activity} actions={actions} />
      </div>
      <Overview activity={activity} />
      {activity.route ? (
        <MapView route={activity.route} className="h-96 w-full rounded-md" />
      ) : (
        <p className="text-sm text-muted-foreground">Pas de trace publique.</p>
      )}
      <ActivityMediaSection activity={activity} actions={actions} />
      <ActivityCommentsSection activity={activity} actions={actions} />
      <ActivityExtrasSection activity={activity} />
    </div>
  );
}
