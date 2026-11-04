"use client";

import { CartesianGrid, Line, LineChart, XAxis, YAxis } from "recharts";
import type { AdminGrowthStats } from "@repo/contracts";
import { Card, CardContent, CardHeader, CardTitle } from "@repo/ui/components/card";
import {
  ChartContainer,
  ChartLegend,
  ChartLegendContent,
  ChartTooltip,
  ChartTooltipContent,
  type ChartConfig,
} from "@repo/ui/components/chart";

const chartConfig = {
  signUps: { label: "Inscriptions", color: "var(--chart-1)" },
  activities: { label: "Activités", color: "var(--chart-2)" },
} satisfies ChartConfig;

const dayFormat = new Intl.DateTimeFormat("fr-FR", { day: "numeric", month: "short", timeZone: "UTC" });

/** `YYYY-MM-DD` (a Paris day) as "4 nov.". */
function formatDay(day: string): string {
  return dayFormat.format(new Date(`${day}T00:00:00Z`));
}

/** Sign-ups and Activities per Paris day of the period (ADR-038 §15). */
export function GrowthChart({ daily }: { daily: AdminGrowthStats["daily"] }) {
  return (
    <Card className="gap-2 py-4">
      <CardHeader className="px-4">
        <CardTitle className="text-sm font-medium">Inscriptions et Activités par jour</CardTitle>
      </CardHeader>
      <CardContent className="px-4">
        <ChartContainer config={chartConfig} className="aspect-auto h-64 w-full">
          <LineChart data={daily} margin={{ left: 0, right: 12, top: 8 }}>
            <CartesianGrid vertical={false} />
            <XAxis dataKey="day" tickLine={false} axisLine={false} tickMargin={8} minTickGap={24} tickFormatter={formatDay} />
            <YAxis tickLine={false} axisLine={false} allowDecimals={false} width={32} />
            <ChartTooltip content={<ChartTooltipContent labelFormatter={(value) => formatDay(String(value))} />} />
            <ChartLegend content={<ChartLegendContent />} />
            <Line dataKey="signUps" type="monotone" stroke="var(--color-signUps)" strokeWidth={2} dot={false} />
            <Line dataKey="activities" type="monotone" stroke="var(--color-activities)" strokeWidth={2} dot={false} />
          </LineChart>
        </ChartContainer>
      </CardContent>
    </Card>
  );
}
