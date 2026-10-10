import Foundation

/// French strings of saving and listing Itineraries.
enum ItineraryMessages {
    static let myItineraries = "Mes Itinéraires"
    static let create = "Créer"
    static let connectionRequired = "Connexion requise"
    static let emptyTitle = "Aucun Itinéraire"
    static let emptyDescription = "Tracez votre prochaine sortie sur la carte : elle apparaîtra ici, même hors ligne."
    static let offline = "Hors ligne : Itinéraires enregistrés sur l'appareil."
    static let syncFailed = "Actualisation impossible pour le moment."

    static func saveIssue(_ issue: ItinerarySaveIssue) -> String {
        switch issue {
        case .incomplete: "Placez un départ et une arrivée pour enregistrer."
        case .legsComputing: "Calcul du tracé en cours : patientez avant d'enregistrer."
        case .legsPending: "Un tronçon est en attente : il sera recalculé au retour du réseau, puis vous pourrez enregistrer."
        case .invalidName: "Le nom doit compter de 1 à 100 caractères."
        }
    }

    static func saveFailed(_ error: ItineraryError) -> String {
        switch error {
        case .unavailable: "Altitudes momentanément indisponibles : votre Itinéraire n'est pas encore enregistré."
        case .offline: "Vous êtes hors ligne : votre Itinéraire n'est pas encore enregistré."
        case .network, .server: "Enregistrement impossible pour le moment : votre Itinéraire n'est pas encore enregistré."
        case .unauthorized: "Votre session a expiré, reconnectez-vous."
        case .invalid, .notFound, .conflict: "L'Itinéraire a été refusé par le serveur."
        }
    }

    static func syncFailed(_ error: ItineraryError) -> String {
        error == .offline ? offline : syncFailed
    }
}
