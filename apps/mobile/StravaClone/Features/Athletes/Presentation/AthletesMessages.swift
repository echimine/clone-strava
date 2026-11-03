import Foundation

/// French strings of another athlete's profile and the follow button (ADR-036 §1, §3).
enum AthletesMessages {
    static let follow = "Suivre"
    static let requestSent = "Demande envoyée"
    static let following = "Abonné"
    static let unfollow = "Se désabonner"
    static let cancelRequestHint = "Annule la demande"
    static let followFailed = "L'abonnement n'a pas abouti, réessayez."
    static let unfollowFailed = "Le désabonnement n'a pas abouti, réessayez."
    static let cancelFailed = "La demande n'a pas pu être annulée, réessayez."
    static let errorTitle = "Profil indisponible"
    static let retry = "Réessayer"
    static let statistics = "Statistiques"
    static let emptyActivitiesTitle = "Aucune activité"
    static let emptyActivitiesDescription = "Aucune activité visible pour l'instant."
    static let openActivity = "Ouvrir l'activité"

    // Followers and following lists, follow requests (ADR-036 §1).
    static let followRequests = "Demandes d'abonnement"
    static let accept = "Accepter"
    static let refuse = "Refuser"
    static let acceptFailed = "La demande n'a pas pu être acceptée, réessayez."
    static let refuseFailed = "La demande n'a pas pu être refusée, réessayez."
    static let remove = "Retirer"
    static let emptyFollowersTitle = "Aucun abonné"
    static let emptyFollowingTitle = "Aucun abonnement"
    static let emptyRequestsTitle = "Aucune demande"
    static let emptyRequestsDescription = "Les demandes d'abonnement en attente s'affichent ici."

    // Search (ADR-036 §2).
    static let searchTitle = "Rechercher"
    static let searchPrompt = "Rechercher un athlète"
    static let searchHint = "Saisissez au moins 2 lettres d'un prénom ou d'un nom."
    static let searchEmptyTitle = "Aucun athlète trouvé"
    static let searchEmptyDescription = "Vérifiez l'orthographe ou essayez un autre nom."

    /// The segments: "Abonnés · 12", "Abonnements · 8".
    static func listTitle(_ list: AthleteFollowsRequest.Kind, count: Int) -> String {
        switch list {
        case .followers: "Abonnés · \(count)"
        case .following: "Abonnements · \(count)"
        }
    }

    static func removeFollowerTitle(_ name: String) -> String {
        "Retirer \(name) de vos abonnés ?"
    }

    static let removeFollowerMessage = "Cette personne ne sera pas prévenue. Elle pourra s'abonner de nouveau."

    static func pendingRequests(_ count: Int) -> String {
        count == 1 ? "1 demande en attente" : "\(count) demandes en attente"
    }

    enum Tab: Hashable, CaseIterable {
        case activities, more
    }

    static func tab(_ tab: Tab) -> String {
        switch tab {
        case .activities: "Activités"
        case .more: "Plus"
        }
    }

    static func activityCount(_ count: Int) -> String {
        count == 1 ? "1 activité" : "\(count) activités"
    }

    static func followers(_ count: Int) -> String {
        count == 1 ? "1 abonné" : "\(count) abonnés"
    }

    static func following(_ count: Int) -> String {
        count == 1 ? "1 abonnement" : "\(count) abonnements"
    }

    /// "Cette année : 412 km" (ADR-036 §4).
    static func thisYear(_ distance: Distance?) -> String {
        "Cette année : \(distance.map(ActivityFormatters.distance) ?? "–")"
    }

    /// The avatars before the counters: "Suivi par Léa et Hugo".
    static func followersYouKnow(_ athletes: [ActivityAuthor]) -> String {
        "Suivi par " + athletes.map(\.displayName).joined(separator: " et ")
    }

    static func kudosFailed(_ error: AthleteError) -> String {
        error == .offline ? message(for: error) : "Le kudos n'a pas pu être envoyé, réessayez."
    }

    static func message(for error: AthleteError) -> String {
        switch error {
        case .offline: "Vous êtes hors ligne."
        case .unauthorized: "Votre session a expiré, reconnectez-vous."
        case .notFound: "Ce profil n'est plus disponible."
        case .server, .network: "Une erreur est survenue, réessayez."
        }
    }
}
