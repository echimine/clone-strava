"use client";

import { formatDistanceStrict } from "date-fns";
import { fr } from "date-fns/locale";
import { Skeleton } from "@repo/ui/components/skeleton";
import { cn } from "@repo/ui/lib/utils";
import { useTodoStats } from "@/features/dashboard/hooks/useTodoStats";
import { TODO_LINKS } from "@/features/dashboard/lib/links";
import { StatTile } from "./StatTile";

/** Past this age, the oldest open Report shows in red (ADR-038 §15). */
const OVERDUE_REPORT_MS = 24 * 3_600_000;

/** "À traiter" (ADR-038 §15): the work waiting now, refreshed every 60 s. */
export function TodoBand() {
  const { data, dataUpdatedAt } = useTodoStats();

  return (
    <section aria-labelledby="todo-band" className="flex flex-col gap-3">
      <h2 id="todo-band" className="text-lg font-semibold">
        À traiter
      </h2>
      {data ? (
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
          <StatTile
            label="Signalements ouverts"
            value={data.openReports.count}
            href={TODO_LINKS.openReports}
            footer={<OldestReport openedAt={data.openReports.oldestOpenedAt} readAt={dataUpdatedAt} />}
          />
          <StatTile label="Activités en échec" value={data.failedActivities} href={TODO_LINKS.failedActivities} />
          <StatTile
            label="Imports en échec"
            value={data.failedImports}
            href={TODO_LINKS.failedImports}
            footer="Sur 7 jours"
          />
          <StatTile
            label="Jobs en échec"
            value={data.failedJobs}
            href={TODO_LINKS.failedJobs}
            footer="Toutes files"
          />
          <StatTile label="Efforts à vérifier" value={data.suspiciousEfforts} href={TODO_LINKS.suspiciousEfforts} />
        </div>
      ) : (
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
          {Array.from({ length: 5 }, (_, index) => (
            <Skeleton key={index} className="h-24" />
          ))}
        </div>
      )}
    </section>
  );
}

/** The oldest open Report's age when the counts were read (`readAt`, refreshed every 60 s). */
function OldestReport({ openedAt, readAt }: { openedAt: string | null; readAt: number }) {
  if (!openedAt) {
    return <span>Aucun en attente</span>;
  }
  const opened = new Date(openedAt);
  const overdue = readAt - opened.getTime() > OVERDUE_REPORT_MS;
  return (
    <span className={cn(overdue && "font-medium text-destructive")}>
      Plus ancien : {formatDistanceStrict(opened, readAt, { locale: fr, addSuffix: true })}
    </span>
  );
}
