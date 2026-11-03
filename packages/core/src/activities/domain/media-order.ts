/**
 * The positions after a `PATCH … { mediaOrder }` (ADR-037 §8). `currentIds`: the Activity's
 * confirmed Media in read order. A known id takes its index in `wantedOrder` (an index left free
 * by an unknown id stays free for the Media still being sent, which confirms with it); a Media
 * missing from `wantedOrder` goes after the whole list, in its current order. Ids of
 * `wantedOrder` that are not in `currentIds` are ignored.
 */
export function mediaPositions(currentIds: readonly string[], wantedOrder: readonly string[]): Map<string, number> {
  const current = new Set(currentIds);
  const positions = new Map<string, number>();
  wantedOrder.forEach((id, index) => {
    if (current.has(id)) {
      positions.set(id, index);
    }
  });
  let next = wantedOrder.length;
  for (const id of currentIds) {
    if (!positions.has(id)) {
      positions.set(id, next);
      next += 1;
    }
  }
  return positions;
}
