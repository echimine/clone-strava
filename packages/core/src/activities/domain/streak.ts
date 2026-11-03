import { addDays, athleteWeekStart } from "./athlete-weeks.js";

/**
 * The Streak (ADR-036 §4): the number of consecutive weeks, ending with the week holding `now`,
 * that each have at least one Activity. An empty current week does not break it: the count then
 * ends with the previous week. `activeWeekStarts` are the Mondays (`YYYY-MM-DD`) of the weeks
 * with an Activity, in any order.
 */
export function streakWeeks(activeWeekStarts: Iterable<string>, now: Date): number {
  const active = new Set(activeWeekStarts);
  let week = athleteWeekStart(now);
  if (!active.has(week)) {
    week = addDays(week, -7);
  }
  let count = 0;
  while (active.has(week)) {
    count += 1;
    week = addDays(week, -7);
  }
  return count;
}
