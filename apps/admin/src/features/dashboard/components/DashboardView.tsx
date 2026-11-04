"use client";

import { ExternalLink } from "lucide-react";
import { useState } from "react";
import { ADMIN_DEFAULT_STATS_PERIOD, type AdminStatsPeriod } from "@repo/contracts";
import { Button } from "@repo/ui/components/button";
import { POSTHOG_PROJECT_URL } from "@/features/dashboard/lib/links";
import { GrowthBand } from "./GrowthBand";
import { TodoBand } from "./TodoBand";

/**
 * The backoffice dashboard (ADR-038 §15): "À traiter" and "Croissance", from our database only.
 * The app's usage stays in PostHog.
 */
export function DashboardView() {
  const [period, setPeriod] = useState<AdminStatsPeriod>(ADMIN_DEFAULT_STATS_PERIOD);

  return (
    <div className="flex flex-col gap-8">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h1 className="text-2xl font-semibold">Tableau de bord</h1>
        <Button asChild variant="outline" size="sm">
          <a href={POSTHOG_PROJECT_URL} target="_blank" rel="noreferrer">
            Ouvrir PostHog
            <ExternalLink aria-hidden />
          </a>
        </Button>
      </div>
      <TodoBand />
      <GrowthBand period={period} onPeriodChange={setPeriod} />
    </div>
  );
}
