import { and, gte, lt, notInArray, sql, type AnyColumn, type SQL } from "drizzle-orm";
import { ADMIN_TIME_ZONE } from "./admin-list.js";

/**
 * Server side of the backoffice dashboard counts (ADR-038 §15): each module counts its own rows
 * with these, computed on the fly, so periods, Paris days and the Administrators left out behave
 * the same in every module.
 */

/** The instants `[start, end)` a count covers. */
export interface InstantRange {
  start: Date;
  end: Date;
}

/** `column >= start and column < end`. */
export function withinRange(column: AnyColumn, range: InstantRange): SQL {
  return and(gte(column, range.start), lt(column, range.end))!;
}

/**
 * Leaves out the rows of `excludedUserIds` (the Administrators, ADR-038 §15); nothing to add
 * when the list is empty.
 */
export function notByUsers(column: AnyColumn, excludedUserIds: readonly string[]): SQL | undefined {
  return excludedUserIds.length > 0 ? notInArray(column, [...excludedUserIds]) : undefined;
}

/** The Paris calendar day of a `timestamptz` column, `YYYY-MM-DD`, to group a count by day. */
export function parisDay(column: AnyColumn): SQL<string> {
  return sql<string>`to_char(${column} at time zone ${sql.raw(`'${ADMIN_TIME_ZONE}'`)}, 'YYYY-MM-DD')`;
}

/** Rows of `{ day, total }` as a map from Paris day to count (absent days are 0). */
export function countsByDay(rows: { day: string; total: number }[]): Map<string, number> {
  return new Map(rows.map((row) => [row.day, Number(row.total)]));
}
