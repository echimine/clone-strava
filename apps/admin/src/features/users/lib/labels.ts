import {
  BAN_DURATION_SECONDS,
  type AdminUserBan,
  type AdminUserState,
  type AthleteLevel,
  type BanDuration,
  type ReportCaseStatus,
  type ReportReason,
  type ReportTargetType,
  type SignInMethod,
  type UserRole,
  type Visibility,
} from "@repo/contracts";

export const roleLabels: Record<UserRole, string> = { user: "Athlète", admin: "Admin" };

export const stateLabels: Record<AdminUserState, string> = {
  active: "Actif",
  banned: "Banni définitivement",
  temporarily_banned: "Banni temporairement",
};

export const methodLabels: Record<SignInMethod, string> = {
  email_code: "Code e-mail",
  google: "Google",
  password: "Mot de passe",
};

export const levelLabels: Record<AthleteLevel, string> = {
  beginner: "Débutant",
  intermediate: "Intermédiaire",
  advanced: "Confirmé",
  professional: "Professionnel",
};

export const visibilityLabels: Record<Visibility, string> = {
  public: "Publique",
  followers: "Abonnés",
  private: "Privée",
};

export const banDurationLabels: Record<BanDuration, string> = {
  "24h": "24 h",
  "7d": "7 jours",
  "30d": "30 jours",
  permanent: "Définitif",
};

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
};

export const caseStatusLabels: Record<ReportCaseStatus, string> = {
  open: "Ouvert",
  actioned: "Sanctionné",
  dismissed: "Rejeté",
  target_gone: "Cible supprimée",
};

/** The sports of the catalog; an unknown code shows as is. */
const sportLabels: Record<string, string> = {
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
const date = new Intl.DateTimeFormat("fr-FR", { timeZone: "Europe/Paris", dateStyle: "short" });
const longDateTime = new Intl.DateTimeFormat("fr-FR", {
  timeZone: "Europe/Paris",
  dateStyle: "long",
  timeStyle: "short",
});

/** A date and time in Paris, as the backoffice shows them. */
export function formatDateTime(iso: string): string {
  return dateTime.format(new Date(iso));
}

export function formatDate(iso: string | null): string {
  return iso ? date.format(new Date(iso)) : "—";
}

/** « Banni jusqu'au 11/11/2026 14:30 » or « Banni définitivement ». */
export function banLabel(ban: AdminUserBan): string {
  return ban.until ? `Banni jusqu'au ${formatDateTime(ban.until)}` : "Banni définitivement";
}

/** What the Ban dialog repeats before confirming: the end of a Ban of `duration` from `now`. */
export function banEndLabel(duration: BanDuration, now: Date): string {
  if (duration === "permanent") {
    return "définitivement";
  }
  return `jusqu'au ${longDateTime.format(new Date(now.getTime() + BAN_DURATION_SECONDS[duration] * 1000))}`;
}
