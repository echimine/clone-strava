/** Number of pages of a list, at least one (an empty list still has its page 1). */
export function pageCount(total: number, pageSize: number): number {
  return Math.max(1, Math.ceil(total / pageSize));
}

/**
 * The page numbers a table shows (ADR-038 §2): the first and last pages, the current one and its
 * neighbours, and `"gap"` where pages are skipped. A gap never hides a single page.
 */
export function pageNumbers(current: number, last: number): (number | "gap")[] {
  const shown = new Set([1, last, current - 1, current, current + 1].filter((page) => page >= 1 && page <= last));
  const sorted = [...shown].sort((a, b) => a - b);
  const result: (number | "gap")[] = [];
  for (const page of sorted) {
    const previous = result.at(-1);
    if (typeof previous === "number" && page - previous === 2) {
      result.push(previous + 1);
    } else if (typeof previous === "number" && page - previous > 2) {
      result.push("gap");
    }
    result.push(page);
  }
  return result;
}
