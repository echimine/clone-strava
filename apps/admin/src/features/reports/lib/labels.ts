import {
  BAN_DURATION_SECONDS,
  REPORT_CASE_OVERDUE_HOURS,
  reportReasonSchema,
  type BanDuration,
  type ReportCaseStatus,
  type ReportReason,
  type ReportTargetType,
} from "@repo/contracts";

/** The app's reason labels (ADR-038 §9). */
export const reportReasonLabels: Record<ReportReason, string> = {
  spam: "Spam ou publicité",
  harassment: "Harcèlement ou propos haineux",
  sexual_or_violent: "Contenu sexuel ou violent",
  impersonation: "Usurpation d'identité",
  other: "Autre",
};

export const reportTargetLabels: Record<ReportTargetType, string> = {
  comment: "Commentaire",
  activity: "Activité",
  athlete: "Profil",
  segment: "Segment",
};

/** A case's outcome (ADR-038 §10). */
export const caseStatusLabels: Record<ReportCaseStatus, string> = {
  open: "À traiter",
  actioned: "Sanctionné",
  dismissed: "Rejeté",
  target_gone: "Cible supprimée",
};

export const caseStatusVariants: Record<ReportCaseStatus, "default" | "secondary" | "destructive" | "outline"> = {
  open: "default",
  actioned: "destructive",
  dismissed: "secondary",
  target_gone: "outline",
};

export const banDurationLabels: Record<BanDuration, string> = {
  "24h": "24 h",
  "7d": "7 jours",
  "30d": "30 jours",
  permanent: "Définitif",
};

/** Reasons in the list's order, joined. */
export function reasonsLabel(reasons: ReportReason[]): string {
  return reportReasonSchema.options
    .filter((reason) => reasons.includes(reason))
    .map((reason) => reportReasonLabels[reason])
    .join(", ");
}

/** Whether an open case waits for more than 24 h (red badge). */
export function isOverdue(openedAt: string, now: number): boolean {
  return now - new Date(openedAt).getTime() > REPORT_CASE_OVERDUE_HOURS * 3_600_000;
}

/** « 3 j », « 5 h », « 12 min »: how long since `iso`. */
export function ageLabel(iso: string, now: number): string {
  const minutes = Math.max(0, Math.floor((now - new Date(iso).getTime()) / 60_000));
  if (minutes < 60) {
    return `${minutes} min`;
  }
  const hours = Math.floor(minutes / 60);
  return hours < 48 ? `${hours} h` : `${Math.floor(hours / 24)} j`;
}

const dateTime = new Intl.DateTimeFormat("fr-FR", { timeZone: "Europe/Paris", dateStyle: "short", timeStyle: "short" });
const longDateTime = new Intl.DateTimeFormat("fr-FR", { timeZone: "Europe/Paris", dateStyle: "long", timeStyle: "short" });

/** A date and time in Paris, as the backoffice shows them. */
export function formatDateTime(iso: string): string {
  return dateTime.format(new Date(iso));
}

/** What the Ban dialog repeats before confirming: the end of a Ban of `duration` from `now`. */
export function banEndLabel(duration: BanDuration, now: Date): string {
  if (duration === "permanent") {
    return "définitivement";
  }
  return `jusqu'au ${longDateTime.format(new Date(now.getTime() + BAN_DURATION_SECONDS[duration] * 1000))}`;
}
