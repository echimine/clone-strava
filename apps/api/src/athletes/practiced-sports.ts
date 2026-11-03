/**
 * `practicedSports` of a profile (ADR-036 §3): the athlete's Practiced sports in their order,
 * then every other sport of their visible Activities, most Activities first.
 * `sportActivityCounts` is already in that order.
 */
export function orderPracticedSports(
  practiced: readonly string[],
  sportActivityCounts: readonly { sportTypeCode: string }[],
): string[] {
  const ordered = [...practiced];
  for (const { sportTypeCode } of sportActivityCounts) {
    if (!ordered.includes(sportTypeCode)) {
      ordered.push(sportTypeCode);
    }
  }
  return ordered;
}
