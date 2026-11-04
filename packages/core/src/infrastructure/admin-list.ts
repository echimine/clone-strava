import { asc, desc, sql, type AnyColumn, type SQL } from "drizzle-orm";

/**
 * Server side of the backoffice list conventions (ADR-038 §2): every admin list repository reads
 * its page with these, so pagination, search, sort and periods behave the same everywhere. The
 * matching query schemas are in `@repo/contracts` (`adminListQuerySchema`, `adminSortQuerySchema`,
 * `adminPeriodShape`, `adminListResponseSchema`).
 */

/** The time zone backoffice days are cut in. */
export const ADMIN_TIME_ZONE = "Europe/Paris";

const DAY_MS = 86_400_000;

/** `{ page, pageSize }` as SQL `limit` and `offset`. */
export function offsetPage(query: { page: number; pageSize: number }): { limit: number; offset: number } {
  return { limit: query.pageSize, offset: (query.page - 1) * query.pageSize };
}

/** One page of a list: `{ items, total, page, pageSize }`. */
export function toOffsetPage<Item>(
  items: Item[],
  total: number,
  query: { page: number; pageSize: number },
): { items: Item[]; total: number; page: number; pageSize: number } {
  return { items, total, page: query.page, pageSize: query.pageSize };
}

/**
 * A period of whole Paris days (`YYYY-MM-DD`, both included) as instants: `start` is the first
 * day's midnight, `end` the midnight after the last day (exclusive). A missing day leaves its
 * bound out. Filter with `column >= start and column < end`.
 */
export function parisDayRange(period: { from?: string; to?: string }): { start?: Date; end?: Date } {
  return {
    ...(period.from ? { start: zonedMidnight(period.from) } : {}),
    ...(period.to ? { end: zonedMidnight(nextDay(period.to)) } : {}),
  };
}

/**
 * Case- and accent-insensitive "contains" over one or more text expressions, joined by a space
 * (`unaccent` + `ILIKE`, ADR-038 §2). `%`, `_` and `\` in the search match themselves.
 *
 *     where(containsIgnoringAccents([profile.firstName, profile.lastName, user.email], query.q))
 */
export function containsIgnoringAccents(expressions: (AnyColumn | SQL)[], search: string): SQL {
  const haystack = sql`unaccent(concat_ws(' ', ${sql.join(expressions, sql`, `)}))`;
  const pattern = `%${escapeLikePattern(search)}%`;
  return sql`${haystack} ilike unaccent(${pattern})`;
}

/**
 * `order by` for a whitelisted sort (ADR-038 §2): the field's column in the requested order,
 * then the tiebreakers (typically the id) so offset pages never overlap.
 */
export function orderByField<Field extends string>(
  columns: Record<Field, AnyColumn | SQL>,
  sort: { sort: Field; order: "asc" | "desc" },
  ...tiebreakers: (AnyColumn | SQL)[]
): SQL[] {
  const direction = sort.order === "asc" ? asc : desc;
  return [direction(columns[sort.sort]), ...tiebreakers.map((column) => direction(column))];
}

/** Escapes `ILIKE` wildcards so `%`, `_` and `\` match themselves. */
function escapeLikePattern(text: string): string {
  return text.replace(/[\\%_]/g, (character) => `\\${character}`);
}

function nextDay(date: string): string {
  return new Date(Date.parse(`${date}T00:00:00Z`) + DAY_MS).toISOString().slice(0, 10);
}

/** Midnight of `date` in Paris as an instant. Paris never changes its clocks at midnight. */
function zonedMidnight(date: string): Date {
  const utcMidnight = Date.parse(`${date}T00:00:00Z`);
  return new Date(utcMidnight - offsetAt(new Date(utcMidnight)));
}

/** Paris's offset from UTC at `instant`, in milliseconds. */
function offsetAt(instant: Date): number {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: ADMIN_TIME_ZONE,
    hourCycle: "h23",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  }).formatToParts(instant);
  const part = (type: Intl.DateTimeFormatPartTypes) => Number(parts.find((p) => p.type === type)?.value);
  const asUtc = Date.UTC(part("year"), part("month") - 1, part("day"), part("hour"), part("minute"), part("second"));
  return asUtc - instant.getTime();
}
