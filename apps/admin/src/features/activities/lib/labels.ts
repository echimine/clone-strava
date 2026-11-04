import type { ActivityImportStatus, ActivitySource, ProcessingStatus, Visibility } from "@repo/contracts";

export const statusLabels: Record<ProcessingStatus, string> = {
  pending: "En attente",
  processing: "En traitement",
  processed: "Traitée",
  failed: "Échec",
};

export const statusVariants: Record<ProcessingStatus, "secondary" | "default" | "destructive"> = {
  pending: "secondary",
  processing: "secondary",
  processed: "default",
  failed: "destructive",
};

export const sourceLabels: Record<ActivitySource, string> = {
  recorded: "Enregistrée",
  imported: "Importée",
  manual: "Saisie",
};

export const visibilityLabels: Record<Visibility, string> = {
  public: "Publique",
  followers: "Abonnés",
  private: "Privée",
};

export const importStatusLabels: Record<ActivityImportStatus, string> = {
  pending: "En attente",
  processing: "En traitement",
  imported: "Importé",
  duplicate: "Doublon",
  failed: "Échec",
};

/** The sports of the catalog (`sports.sport_type`); an unknown code shows as is. */
export const sportLabels: Record<string, string> = {
  run: "Course à pied",
  ride: "Vélo",
  swim: "Natation",
  walk: "Marche",
  hike: "Randonnée",
};

export function sportLabel(code: string): string {
  return sportLabels[code] ?? code;
}

const dateTime = new Intl.DateTimeFormat("fr-FR", { timeZone: "Europe/Paris", dateStyle: "short", timeStyle: "short" });

/** A date and time in Paris, as the backoffice shows them. */
export function formatDateTime(iso: string): string {
  return dateTime.format(new Date(iso));
}

const kilometres = new Intl.NumberFormat("fr-FR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });

/** `10012.5` → `10,01 km`; a dash without a value. */
export function formatDistance(metres: number | null): string {
  return metres === null ? "—" : `${kilometres.format(metres / 1000)} km`;
}

/** `3000` → `50 min`, `3720` → `1 h 02`; a dash without a value. */
export function formatDuration(seconds: number | null): string {
  if (seconds === null) {
    return "—";
  }
  const minutes = Math.round(seconds / 60);
  const hours = Math.floor(minutes / 60);
  return hours === 0 ? `${minutes} min` : `${hours} h ${String(minutes % 60).padStart(2, "0")}`;
}
