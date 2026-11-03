/**
 * Weeks of an athlete (ADR-036 §4): Monday 00:00 to Sunday 24:00 in a single time zone, since no
 * per-athlete time zone is stored. Days and weeks are calendar dates `YYYY-MM-DD`; a week is
 * named by its Monday.
 */
export const ATHLETE_TIME_ZONE = "Europe/Paris";

const DAY_MS = 86_400_000;

/** The calendar date of `instant` in `timeZone`, as `YYYY-MM-DD`. */
export function athleteLocalDate(instant: Date, timeZone = ATHLETE_TIME_ZONE): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(instant);
  const part = (type: Intl.DateTimeFormatPartTypes) => parts.find((p) => p.type === type)?.value ?? "";
  return `${part("year")}-${part("month")}-${part("day")}`;
}

/** `date` (`YYYY-MM-DD`) shifted by `days` calendar days. */
export function addDays(date: string, days: number): string {
  return new Date(Date.parse(`${date}T00:00:00Z`) + days * DAY_MS).toISOString().slice(0, 10);
}

/** The Monday of the week holding the calendar date `date`. */
export function mondayOf(date: string): string {
  const weekday = new Date(`${date}T00:00:00Z`).getUTCDay(); // 0 = Sunday
  return addDays(date, -((weekday + 6) % 7));
}

/** The Monday of the athlete's week holding `instant`. */
export function athleteWeekStart(instant: Date, timeZone = ATHLETE_TIME_ZONE): string {
  return mondayOf(athleteLocalDate(instant, timeZone));
}

/** An athlete's totals over one week (ADR-036 §4, `GET /v1/me/progress`). */
export interface WeekTotals {
  /** The week's Monday, `YYYY-MM-DD`. */
  weekStart: string;
  distanceM: number;
  elevationGainM: number;
  movingTimeS: number;
  activityCount: number;
}

/**
 * The `count` weeks ending with the one holding `now`, oldest first, each with its totals from
 * `totals` (one row per week that had Activities) or zeros. Rows outside the window are ignored.
 */
export function zeroFilledWeeks(now: Date, count: number, totals: readonly WeekTotals[]): WeekTotals[] {
  const byWeek = new Map(totals.map((row) => [row.weekStart, row]));
  const current = athleteWeekStart(now);
  return Array.from({ length: count }, (_, index) => {
    const weekStart = addDays(current, (index - count + 1) * 7);
    const row = byWeek.get(weekStart);
    return {
      weekStart,
      distanceM: row?.distanceM ?? 0,
      elevationGainM: row?.elevationGainM ?? 0,
      movingTimeS: row?.movingTimeS ?? 0,
      activityCount: row?.activityCount ?? 0,
    };
  });
}
