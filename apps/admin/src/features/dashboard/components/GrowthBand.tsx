"use client";

import type { AdminStatsPeriod, AdminTrend } from "@repo/contracts";
import { ADMIN_STATS_PERIODS } from "@repo/contracts";
import { Button } from "@repo/ui/components/button";
import { Skeleton } from "@repo/ui/components/skeleton";
import { cn } from "@repo/ui/lib/utils";
import { useGrowthStats } from "@/features/dashboard/hooks/useGrowthStats";
import { describeChange } from "@/features/dashboard/lib/change";
import { GrowthChart } from "./GrowthChart";
import { formatCount, StatTile } from "./StatTile";

const PERIOD_LABELS: Record<AdminStatsPeriod, string> = { "7d": "7 j", "30d": "30 j", "90d": "90 j" };

/**
 * "Croissance" (ADR-038 §15): the last 7, 30 or 90 Paris days, each figure with its change versus
 * the previous period of the same length, and the daily chart of sign-ups and Activities.
 */
export function GrowthBand({
  period,
  onPeriodChange,
}: {
  period: AdminStatsPeriod;
  onPeriodChange: (period: AdminStatsPeriod) => void;
}) {
  const { data } = useGrowthStats(period);
  const trendTile = (label: string, trend: AdminTrend, extra?: string) => (
    <StatTile
      label={label}
      value={trend.value}
      footer={
        <div className="flex flex-col gap-0.5">
          <ChangeLine trend={trend} period={period} />
          {extra ? <span>{extra}</span> : null}
        </div>
      }
    />
  );

  return (
    <section aria-labelledby="growth-band" className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h2 id="growth-band" className="text-lg font-semibold">
          Croissance
        </h2>
        <div role="group" aria-label="Période" className="flex gap-1">
          {ADMIN_STATS_PERIODS.map((option) => (
            <Button
              key={option}
              size="sm"
              variant={option === period ? "default" : "outline"}
              aria-pressed={option === period}
              onClick={() => onPeriodChange(option)}
            >
              {PERIOD_LABELS[option]}
            </Button>
          ))}
        </div>
      </div>
      {data ? (
        <div className="flex flex-col gap-4">
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {trendTile("Inscriptions", data.signUps)}
            {trendTile("Athlètes actifs", data.activeAthletes)}
            {trendTile(
              "Activités",
              data.activities.total,
              `${formatCount(data.activities.recorded.value)} enregistrées · ${formatCount(data.activities.imported.value)} importées · ${formatCount(data.activities.manual.value)} saisies`,
            )}
          </div>
          <GrowthChart daily={data.daily} />
          <h3 className="text-sm font-medium text-muted-foreground">Premium</h3>
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
            <StatTile label="Payants actifs" value={data.premium.payingActive} footer="Aujourd'hui" />
            <StatTile label="Essais en cours" value={data.premium.trialsActive} footer="Aujourd'hui" />
            <StatTile label="Premium offerts actifs" value={data.premium.promotionalActive} footer="Aujourd'hui" />
            {trendTile("Essais démarrés", data.premium.trialsStarted)}
            {trendTile("Nouveaux payants", data.premium.newPaying)}
          </div>
          <h3 className="text-sm font-medium text-muted-foreground">Engagement</h3>
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            {trendTile("Kudos", data.engagement.kudos)}
            {trendTile("Commentaires", data.engagement.comments)}
            {trendTile("Follows", data.engagement.follows)}
            {trendTile("Médias ajoutés", data.engagement.media)}
          </div>
        </div>
      ) : (
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {Array.from({ length: 3 }, (_, index) => (
            <Skeleton key={index} className="h-24" />
          ))}
        </div>
      )}
    </section>
  );
}

function ChangeLine({ trend, period }: { trend: AdminTrend; period: AdminStatsPeriod }) {
  const change = describeChange(trend);
  return (
    <span>
      <span
        className={cn(
          "font-medium",
          change.direction === "up" && "text-emerald-600 dark:text-emerald-400",
          change.direction === "down" && "text-destructive",
        )}
      >
        {change.label}
      </span>{" "}
      vs {PERIOD_LABELS[period]} précédents
    </span>
  );
}
