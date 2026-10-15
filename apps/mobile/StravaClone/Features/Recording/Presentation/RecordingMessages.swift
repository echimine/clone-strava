import Foundation

/// French texts of the Recording screens (ADR-031 §2, §8, §11).
enum RecordingMessages {
    static let fullAccuracyRefused = "La position précise est nécessaire pour enregistrer ton activité."
    static let locationDenied = "L'accès à ta position est désactivé. Autorise-le dans Réglages pour enregistrer une activité."
    static let startFailed = "Impossible de démarrer l'enregistrement."
    static let actionFailed = "Impossible d'enregistrer ce changement. Réessaie."
    static let paused = "En pause"
    static let autoPause = "Pause automatique"
    static let finishTitle = "Terminer l'enregistrement ?"
    static let finishMessage = "Tu pourras encore reprendre depuis l'écran de fin."
    static let deleteTitle = "Supprimer cet enregistrement ?"
    static let saveFailed = "Impossible d'enregistrer l'activité. Réessaie."
    static let traceWriteFailing = "Impossible d'enregistrer la trace : espace insuffisant"
    static let signOutWarning = "L'enregistrement en cours sera supprimé."
    static let deleteMessage = "La trace et les stats seront effacées. Cette action est définitive."
    static let itineraryDeleted = "Cet Itinéraire a été supprimé."
    static let itineraryUnavailableOffline = "Tracé indisponible hors ligne"
    static let noItinerary = "Aucun"
    static let createItinerary = "Créer un Itinéraire"
    static let removeItinerary = "Retirer l'Itinéraire"
    static let removeItineraryTitle = "Retirer l'Itinéraire ?"
    static let removeItineraryMessage = "La distance restante ne sera plus affichée. Tu ne pourras pas en choisir un autre."
    static let remainingOnItinerary = "Restant sur l'Itinéraire"
    static let offItinerary = "Hors Itinéraire"
    static let itineraryFinished = "Itinéraire terminé"

    static func saveBlocker(_ blocker: RecordingSaveBlocker, sport: RecordingSport) -> String {
        switch blocker {
        case .tooShort(let minimum):
            let minutes = Int(minimum.components.seconds) / 60
            return "Une activité \(article(sport)) doit durer au moins \(minutes) min pour être enregistrée."
        case .notEnoughPoints:
            return "Pas assez de positions GPS pour enregistrer cette activité."
        }
    }

    private static func article(_ sport: RecordingSport) -> String {
        switch sport {
        case .run: "de course à pied"
        case .ride: "de vélo"
        case .walk: "de marche"
        case .hike: "de randonnée"
        }
    }
}
