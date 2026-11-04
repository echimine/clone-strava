import type { AuditAction, AuditTargetType } from "@repo/contracts";

/** Each audit action in plain French (ADR-038 §17), in the Journal and its action filter. */
export const auditActionLabels = {
  "user.ban": "Bannissement",
  "user.unban": "Levée du bannissement",
  "user.sign_out": "Déconnexion partout",
  "user.name.reset": "Nom réinitialisé",
  "user.bio.reset": "Bio réinitialisée",
  "user.avatar.reset": "Photo de profil retirée",
  "user.role.grant": "Rôle administrateur attribué",
  "user.role.revoke": "Rôle administrateur retiré",
  "user.delete": "Compte supprimé",
  "user.delete.complete": "Suppression du compte terminée",
  "premium.sync": "Premium resynchronisé",
  "premium.grant": "Premium offert",
  "premium.revoke": "Premium offert retiré",
  "activity.reprocess": "Activité retraitée",
  "activity.recompute": "Activité recalculée",
  "activity.delete": "Activité supprimée",
  "activity.text.reset": "Titre et description réinitialisés",
  "media.remove": "Média retiré",
  "comment.remove": "Commentaire retiré",
  "import.reprocess": "Import retraité",
  "activity.reprocess.batch": "Activités en échec retraitées",
  "activity.recompute.batch": "Recalculs en échec relancés",
  "import.reprocess.batch": "Imports en échec retraités",
  "queue.job.retry": "Job relancé",
  "queue.retry_failed": "Échecs d'une file relancés",
  "queue.pause": "File mise en pause",
  "queue.resume": "File relancée",
  "report.resolve": "Signalement clos : sanctionné",
  "report.dismiss": "Signalement rejeté",
  "effort.accept": "Effort accepté",
  "effort.reject": "Effort rejeté",
  "effort.restore": "Effort rétabli",
  "segment.rename": "Segment renommé",
  "segment.delete": "Segment supprimé",
  "admin.two_factor.enable": "2FA activée",
  "admin.two_factor.disable": "2FA désactivée",
} as const satisfies Record<AuditAction, string>;

export const auditTargetLabels = {
  user: "Athlète",
  activity: "Activité",
  media: "Média",
  comment: "Commentaire",
  activity_import: "Import",
  queue: "File",
  job: "Job",
  report_case: "Signalement",
  segment: "Segment",
  segment_effort: "Effort",
} as const satisfies Record<AuditTargetType, string>;

/** Backoffice page of a target, when it has one. */
export function targetHref(type: AuditTargetType, id: string): string | null {
  switch (type) {
    case "user":
      return `/users/${id}`;
    case "activity":
      return `/activities/${id}`;
    default:
      return null;
  }
}

const dateTime = new Intl.DateTimeFormat("fr-FR", {
  timeZone: "Europe/Paris",
  dateStyle: "short",
  timeStyle: "medium",
});

/** A date and time in Paris, as the backoffice shows them. */
export function formatParisDateTime(iso: string): string {
  return dateTime.format(new Date(iso));
}
