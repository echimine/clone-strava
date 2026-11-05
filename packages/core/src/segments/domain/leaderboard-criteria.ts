import {
  LEADERBOARD_AGE_BANDS,
  LEADERBOARD_PERIODS,
  LEADERBOARD_WEIGHT_BANDS,
  type LeaderboardFilter,
  type LeaderboardGender,
} from "@repo/contracts";

/**
 * Who a Leaderboard keeps (ADR-039 §8): the sex selector, and at most one other filter. Bounds are
 * inclusive lower and exclusive upper, `null` for an open end.
 */
export type LeaderboardCriteria =
  | { kind: "none" }
  | { kind: "period"; unit: "day" | "week" | "month" | "year"; timeZone: string }
  | { kind: "following"; athleteIds: string[] }
  | { kind: "age"; minYears: number | null; maxYearsExclusive: number | null }
  | { kind: "weight"; minKg: number | null; maxKgExclusive: number | null };

/** A `filter`/`value` pair this server does not know: `422 invalid_leaderboard_filter`. */
export class InvalidLeaderboardFilterError extends Error {
  constructor() {
    super("Invalid leaderboard filter");
  }
}

const PERIOD_UNITS = { today: "day", week: "week", month: "month", year: "year" } as const;

/** `"20-24"` → [20, 25); `"0-19"` → [null, 20); `"75+"` → [75, null). */
function band(value: string, bands: readonly string[]): { min: number | null; maxExclusive: number | null } {
  if (!bands.includes(value)) {
    throw new InvalidLeaderboardFilterError();
  }
  if (value.endsWith("+")) {
    return { min: Number(value.slice(0, -1)), maxExclusive: null };
  }
  const [low, high] = value.split("-").map(Number) as [number, number];
  return { min: low === 0 ? null : low, maxExclusive: high + 1 };
}

function isTimeZone(value: string): boolean {
  try {
    new Intl.DateTimeFormat("en", { timeZone: value });
    return true;
  } catch {
    return false;
  }
}

/**
 * The criteria of a Leaderboard query. `followingIds` are the viewer's accepted followees, given
 * by `apps/api` (`social`); the viewer is added. An unknown time zone falls back to UTC.
 */
export function leaderboardCriteria(input: {
  filter: LeaderboardFilter | undefined;
  value: string | undefined;
  timeZone: string | undefined;
  viewerId: string;
  followingIds: readonly string[];
}): LeaderboardCriteria {
  switch (input.filter) {
    case undefined:
      if (input.value !== undefined) {
        throw new InvalidLeaderboardFilterError();
      }
      return { kind: "none" };
    case "period": {
      const value = input.value as (typeof LEADERBOARD_PERIODS)[number] | undefined;
      if (value === undefined || !LEADERBOARD_PERIODS.includes(value)) {
        throw new InvalidLeaderboardFilterError();
      }
      const timeZone = input.timeZone && isTimeZone(input.timeZone) ? input.timeZone : "UTC";
      return { kind: "period", unit: PERIOD_UNITS[value], timeZone };
    }
    case "following":
      if (input.value !== undefined) {
        throw new InvalidLeaderboardFilterError();
      }
      return { kind: "following", athleteIds: [...new Set([...input.followingIds, input.viewerId])] };
    case "age": {
      const { min, maxExclusive } = band(input.value ?? "", LEADERBOARD_AGE_BANDS);
      return { kind: "age", minYears: min, maxYearsExclusive: maxExclusive };
    }
    case "weight": {
      const { min, maxExclusive } = band(input.value ?? "", LEADERBOARD_WEIGHT_BANDS);
      return { kind: "weight", minKg: min, maxKgExclusive: maxExclusive };
    }
  }
}

/**
 * ADR-039 §9: without Premium, only Tous with no filter and no cursor; anything else is
 * `403 premium_required`.
 */
export function requiresPremium(query: {
  gender: LeaderboardGender;
  filter?: LeaderboardFilter | undefined;
  cursor?: string | undefined;
}): boolean {
  return query.gender !== "all" || query.filter !== undefined || query.cursor !== undefined;
}

/** Keyset position in a Leaderboard: `(elapsed_time_s, started_at, effort id)`. */
export interface LeaderboardCursor {
  elapsedTimeS: number;
  startedAt: string;
  effortId: string;
}

export class InvalidLeaderboardCursorError extends Error {
  constructor() {
    super("Invalid leaderboard cursor");
  }
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Opaque to clients: base64url of `{elapsedTimeS}|{startedAt}|{effortId}`. */
export function encodeLeaderboardCursor(cursor: LeaderboardCursor): string {
  return Buffer.from(`${cursor.elapsedTimeS}|${cursor.startedAt}|${cursor.effortId}`, "utf8").toString("base64url");
}

export function decodeLeaderboardCursor(value: string): LeaderboardCursor {
  const [time, startedAt, effortId, ...rest] = Buffer.from(value, "base64url").toString("utf8").split("|");
  const elapsedTimeS = Number(time);
  if (
    rest.length > 0 ||
    !Number.isInteger(elapsedTimeS) ||
    elapsedTimeS < 0 ||
    !startedAt ||
    Number.isNaN(Date.parse(startedAt)) ||
    !effortId ||
    !UUID.test(effortId)
  ) {
    throw new InvalidLeaderboardCursorError();
  }
  return { elapsedTimeS, startedAt, effortId };
}
