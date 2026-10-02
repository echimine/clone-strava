const SPORT_LABELS: Record<string, string> = {
  run: "Course à pied",
  ride: "Sortie à vélo",
  swim: "Natation",
  walk: "Marche",
  hike: "Randonnée",
};

/**
 * Title of an imported activity when neither the app nor the file gives
 * one (ADR-028 §5): sport and time of day, as for recorded activities.
 * The user's time zone is not known server-side yet, so the time of day
 * is read in `Europe/Paris`.
 */
export function defaultActivityTitle(sportTypeCode: string, startedAt: Date, timeZone = "Europe/Paris"): string {
  const hour = Number(
    new Intl.DateTimeFormat("en-GB", { hour: "numeric", hourCycle: "h23", timeZone }).format(startedAt),
  );
  const label = SPORT_LABELS[sportTypeCode] ?? "Activité";
  if (hour >= 5 && hour < 12) return `${label} le matin`;
  if (hour >= 12 && hour < 18) return `${label} l'après-midi`;
  if (hour >= 18 && hour < 22) return `${label} le soir`;
  return `${label} de nuit`;
}
