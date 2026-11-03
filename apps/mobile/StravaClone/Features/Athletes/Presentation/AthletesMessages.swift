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
    static let more = "Plus d'options"
    static let errorTitle = "Profil indisponible"
    static let retry = "Réessayer"
    static let statistics = "Statistiques"
    static let emptyActivitiesTitle = "Aucune activité"
    static let emptyActivitiesDescription = "Aucune activité visible pour l'instant."
    static let openActivity = "Ouvrir l'activité"

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

    static func streak(_ weeks: Int) -> String {
        weeks == 1 ? "🔥 1 semaine d'affilée" : "🔥 \(weeks) semaines d'affilée"
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
