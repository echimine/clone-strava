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
        case .server, .network: "Une erreur est survenue, réessayez."
        }
    }
}
