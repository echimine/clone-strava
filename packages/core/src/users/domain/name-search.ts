/** Athlete search (ADR-036 §2): no pagination, "refine your search". */
export const NAME_SEARCH_LIMIT = 20;

export const NAME_QUERY_MIN_LENGTH = 2;
export const NAME_QUERY_MAX_LENGTH = 50;

/**
 * The trimmed search text, or `null` when it is missing or not 2 to 50
 * characters long (ADR-036 §2).
 */
export function parseNameQuery(raw: string | undefined): string | null {
  const query = (raw ?? "").trim();
  const length = [...query].length;
  return length >= NAME_QUERY_MIN_LENGTH && length <= NAME_QUERY_MAX_LENGTH ? query : null;
}

/** Escapes `ILIKE` wildcards so `%`, `_` and `\` in the query match themselves. */
export function escapeLikePattern(text: string): string {
  return text.replace(/[\\%_]/g, (character) => `\\${character}`);
}
