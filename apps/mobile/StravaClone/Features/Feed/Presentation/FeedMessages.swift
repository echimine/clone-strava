import Foundation

/// French strings of the feed.
enum FeedMessages {
    static let emptyTitle = "Aucune activité"
    static let emptyDescription = "Importez ou enregistrez une activité : elle apparaîtra ici, avec celles des athlètes que vous suivez."
    static let errorTitle = "Fil indisponible"
    static let retry = "Réessayer"

    static func message(for error: FeedError) -> String {
        switch error {
        case .offline: "Vous êtes hors ligne."
        case .unauthorized: "Votre session a expiré, reconnectez-vous."
        case .notFound: "Cette activité n'est plus disponible."
        case .server, .network: "Une erreur est survenue, réessayez."
        }
    }

    // MARK: - Local Activities (ADR-031 §14)

    static let delete = "Supprimer"
    static let cancel = "Annuler"
    static let deleteConfirmationTitle = "Supprimer cette activité ?"
    static let deleteConfirmationMessage = "Elle sera supprimée définitivement, sur le téléphone comme sur le serveur."
    static let localActionRefused = "Action impossible : l'activité a changé d'état."

    static func status(_ status: LocalActivityStatus) -> String {
        switch status {
        case .waitingForNetwork: "En attente de réseau"
        case .sending: "Envoi…"
        case .retryingSoon: "Nouvel essai bientôt"
        case .processing: "Traitement…"
        case .failed(let reason): "Échec de l'envoi : \(failureReason(reason))"
        }
    }

    /// The server's code in words (ADR-031 §14 response table, `processingError`).
    static func failureReason(_ code: String) -> String {
        switch code {
        case "validation_error": "activité refusée par le serveur"
        case "id_conflict": "identifiant déjà utilisé"
        case "trace_too_large": "trace trop volumineuse"
        case "activity_failed", "processing_error": "erreur de traitement"
        case "invalid_trace": "trace illisible"
        case "empty_trace": "trace vide"
        default: code
        }
    }

    static func kudosFailed(_ error: FeedError) -> String {
        switch error {
        case .offline: "Kudos non envoyé : vous êtes hors ligne."
        default: "Impossible d'envoyer le kudos."
        }
    }
}
