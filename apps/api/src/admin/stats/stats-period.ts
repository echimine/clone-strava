import type { AdminStatsPeriod } from "@repo/contracts";
import { ADMIN_TIME_ZONE, parisDayRange } from "@repo/core/infrastructure";

/** Instants `[start, end)` a count covers. */
export interface StatsRange {
  start: Date;
  end: Date;
}

/** A Growth period (ADR-038 §15): its Paris days and the two ranges compared. */
export interface StatsPeriodWindow {
  /** The period's Paris days `YYYY-MM-DD`, oldest first, today last. */
  days: string[];
  current: StatsRange;
  /** The same number of days just before `current`. */
  previous: StatsRange;
}

const PERIOD_DAYS: Record<AdminStatsPeriod, number> = { "7d": 7, "30d": 30, "90d": 90 };
const DAY_MS = 86_400_000;

/**
 * The last 7, 30 or 90 Paris days, today included (today is still running), and the as many
 * days before them, as instants cut at Paris midnights.
 */
export function statsPeriodWindow(period: AdminStatsPeriod, now: Date): StatsPeriodWindow {
  const length = PERIOD_DAYS[period];
  const today = parisDate(now);
  const days = Array.from({ length }, (_, index) => shiftDay(today, index - length + 1));
  const first = days[0]!;
  const current = parisDayRange({ from: first, to: today });
  const previous = parisDayRange({ from: shiftDay(first, -length), to: shiftDay(first, -1) });
  return {
    days,
    current: { start: current.start!, end: current.end! },
    previous: { start: previous.start!, end: previous.end! },
  };
}

/** The Paris calendar date of `instant`, `YYYY-MM-DD`. */
function parisDate(instant: Date): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: ADMIN_TIME_ZONE }).format(instant);
}

function shiftDay(date: string, days: number): string {
  return new Date(Date.parse(`${date}T00:00:00Z`) + days * DAY_MS).toISOString().slice(0, 10);
}
