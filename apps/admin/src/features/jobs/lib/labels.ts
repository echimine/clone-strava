import type { AdminQueueScheduler } from "@repo/contracts";

/** The sports of the catalog (`sports.sport_type`); an unknown code shows as is. */
const sportLabels: Record<string, string> = {
  run: "Course à pied",
  ride: "Vélo",
  swim: "Natation",
  walk: "Marche",
  hike: "Randonnée",
};

export function sportLabel(code: string | null): string {
  return code === null ? "—" : (sportLabels[code] ?? code);
}

const dateTime = new Intl.DateTimeFormat("fr-FR", { timeZone: "Europe/Paris", dateStyle: "short", timeStyle: "short" });

/** A date and time in Paris, as the backoffice shows them; a dash without one. */
export function formatDateTime(iso: string | null): string {
  return iso === null ? "—" : dateTime.format(new Date(iso));
}

/** `600000` → `toutes les 10 min`; a cron pattern as is, with its time zone. */
export function schedulerRhythm(scheduler: AdminQueueScheduler): string {
  if (scheduler.everyMs !== null) {
    const minutes = Math.round(scheduler.everyMs / 60_000);
    return minutes % 60 === 0 ? `toutes les ${minutes / 60} h` : `toutes les ${minutes} min`;
  }
  return scheduler.pattern ? `cron ${scheduler.pattern}${scheduler.timeZone ? ` (${scheduler.timeZone})` : ""}` : "—";
}

/** The French name of an athlete for a link; the start of the id once the account is gone. */
export function athleteName(athlete: { id: string; displayName: string }): string {
  return athlete.displayName || athlete.id.slice(0, 8);
}
