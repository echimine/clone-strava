import Foundation

/// French copy of Reports and Blocks (ADR-038 §8, §9).
enum ModerationMessages {
    static let block = "Bloquer"
    static let unblock = "Débloquer"
    static let cancel = "Annuler"
    static let close = "Fermer"
    static let send = "Envoyer"

    static func reportTitle(_ kind: ReportTarget.Kind) -> String {
        switch kind {
        case .comment: "Signaler le commentaire"
        case .activity: "Signaler l'activité"
        case .athlete: "Signaler l'athlète"
        case .segment: "Signaler ce Segment"
        }
    }

    static let reasonHeader = "Motif"
    static let noteHeader = "Précisions"
    static let notePlaceholder = "Ajouter des précisions (facultatif)"
    static let noteRequiredPlaceholder = "Décrivez le problème"
    static func noteFooter(_ reason: ReportReason?) -> String {
        reason == .other
            ? "Obligatoire avec « Autre », \(reportNoteMaxLength) caractères au plus."
            : "\(reportNoteMaxLength) caractères au plus."
    }

    static func reason(_ reason: ReportReason) -> String {
        switch reason {
        case .spam: "Spam ou publicité"
        case .harassment: "Harcèlement ou propos haineux"
        case .sexualOrViolent: "Contenu sexuel ou violent"
        case .impersonation: "Usurpation d'identité"
        case .other: "Autre"
        }
    }

    static let thanks = "Merci, notre équipe va examiner ce signalement"
    static let alreadyReported = "Déjà signalé"
    static let alreadyReportedDetail = "Vous avez déjà signalé ce contenu, notre équipe va l'examiner."
    static func blockToo(_ firstName: String) -> String { "Bloquer aussi \(firstName)" }

    static func blockConfirmationTitle(_ firstName: String) -> String { "Bloquer \(firstName) ?" }
    static let blockConfirmationMessage =
        "Vous ne verrez plus ses Activités et il ne verra plus les vôtres ; vos abonnements mutuels seront supprimés."
    static func blocked(_ firstName: String) -> String { "\(firstName) est bloqué" }

    static let blockedAthletes = "Athlètes bloqués"
    static let noBlockedAthletes = "Aucun athlète bloqué"
    static let noBlockedAthletesDetail = "Les athlètes que vous bloquez apparaissent ici."
    static func unblockConfirmationTitle(_ firstName: String) -> String { "Débloquer \(firstName) ?" }
    static let unblockConfirmationMessage =
        "Vous verrez à nouveau ses Activités et il verra les vôtres. Vos abonnements ne seront pas rétablis."
    static let loadFailedTitle = "Chargement impossible"
    static let retry = "Réessayer"

    static func message(for error: ModerationError) -> String {
        switch error {
        case .offline: "Pas de connexion. Réessayez une fois en ligne."
        case .notFound: "Ce contenu n'est plus disponible."
        case .rateLimited: "Vous avez envoyé trop de signalements aujourd'hui. Réessayez plus tard."
        case .unauthorized: "Votre session a expiré."
        case .network, .server: "Une erreur est survenue. Réessayez."
        }
    }
}
