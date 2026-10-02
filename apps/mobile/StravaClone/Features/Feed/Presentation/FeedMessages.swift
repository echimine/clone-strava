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

    static func kudosFailed(_ error: FeedError) -> String {
        switch error {
        case .offline: "Kudos non envoyé : vous êtes hors ligne."
        default: "Impossible d'envoyer le kudos."
        }
    }
}
