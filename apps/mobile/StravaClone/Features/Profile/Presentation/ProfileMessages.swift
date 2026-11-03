import Foundation

/// French strings of the Profile tab and Réglages (ADR-036 §3, §10).
enum ProfileMessages {
    static let errorTitle = "Profil indisponible"
    static let retry = "Réessayer"
    static let editProfile = "Modifier le profil"
    static let settings = "Réglages"
    static let search = "Rechercher des athlètes"
    static let progressPlaceholder = "Vos progrès arrivent bientôt."
    static let emptyActivitiesTitle = "Aucune activité"
    static let emptyActivitiesDescription = "Enregistrez ou importez une activité : elle apparaîtra ici."
    static let statistics = "Statistiques"
    static let itineraries = "Itinéraires"
    static let myItineraries = "Mes Itinéraires"
    static let firstName = "Prénom"
    static let lastName = "Nom"
    static let save = "Enregistrer"
    static let cancel = "Annuler"
    static let invalidName = "Prénom et nom : de 1 à 50 caractères chacun."
    static let approvalFailed = "Le réglage n'a pas pu être modifié, réessayez."
    static let approveFollowers = "Approuver mes abonnés"
    static let approveFollowersFooter = "Activé, chaque nouvel abonné attend votre accord."

    static func tab(_ tab: ProfileStore.Tab) -> String {
        switch tab {
        case .progress: "Progrès"
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

    static func message(for error: AthleteError) -> String {
        switch error {
        case .offline: "Vous êtes hors ligne."
        case .unauthorized: "Votre session a expiré, reconnectez-vous."
        case .notFound: "Ce profil n'est plus disponible."
        case .server, .network: "Une erreur est survenue, réessayez."
        }
    }
}
