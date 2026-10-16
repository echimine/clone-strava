import Foundation

/// French strings of the Activity detail (ADR-033 §3).
enum ActivityDetailMessages {
    static let errorTitle = "Activité indisponible"
    static let retry = "Réessayer"
    static let unavailableTitle = "Cette activité n'est plus disponible"
    static let back = "Retour"

    static func message(for error: ActivityDetailError) -> String {
        switch error {
        case .offline: "Vous êtes hors ligne."
        case .unauthorized: "Votre session a expiré, reconnectez-vous."
        case .notFound: unavailableTitle
        case .invalid, .server, .network: "Une erreur est survenue, réessayez."
        }
    }

    // MARK: Edit (ADR-033 §7)

    static let edit = "Modifier"
    static let manage = "Gérer l'activité"
    static let editTitle = "Modifier l'activité"
    static let cancel = "Annuler"
    static let save = "Enregistrer"
    static let titleField = "Titre"
    static let descriptionField = "Description"
    static let sportField = "Sport"
    static let visibilityField = "Visibilité"

    static func visibilityLabel(_ visibility: ActivityVisibility) -> String {
        switch visibility {
        case .public: "Tout le monde"
        case .followers: "Abonnés"
        case .private: "Moi uniquement"
        }
    }

    /// The toast of a save that failed; the previous values are back.
    static func editFailed(_ error: ActivityDetailError) -> String {
        switch error {
        case .offline: "Vous êtes hors ligne : la modification n'a pas été enregistrée."
        case .notFound: unavailableTitle
        default: "La modification n'a pas pu être enregistrée."
        }
    }

    /// Under the reopened sheet after a `422`.
    static func editRefused(code: String?) -> String {
        switch code {
        case "activity_too_short_for_sport": "Cette activité est trop courte pour ce sport."
        default: "Vérifiez le titre et la description."
        }
    }
}
