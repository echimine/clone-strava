import Foundation

/// French strings of saving, listing and viewing Itineraries.
enum ItineraryMessages {
    static let trackUnavailableOffline = "Tracé pas encore téléchargé : il s'affichera au retour du réseau."
    static let trackUnavailable = "Tracé indisponible pour le moment."
    static let elevationProfile = "Profil d'altitude"

    /// The elevation gain, "≈" when Open-Meteo provided altitudes (ADR-030 §3).
    static func elevationGain(_ meters: Double, source: ElevationSource?) -> String {
        let gain = ActivityFormatters.elevation(meters)
        return source?.isApproximate == true ? "≈ \(gain)" : gain
    }

    /// Credit of the altitudes (ADR-030 §3).
    static func elevationSource(_ source: ElevationSource) -> String {
        switch source {
        case .ign: "Altitudes : IGN"
        case .mixed: "Altitudes : IGN, Open-Meteo / Copernicus"
        case .openMeteo: "Altitudes : Open-Meteo / Copernicus"
        }
    }

    static let myItineraries = "Mes Itinéraires"
    static let backToList = "Revenir à la liste"
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

    static let sessionExpired = "Votre session a expiré, reconnectez-vous."
    static let gone = "Cet Itinéraire n'existe plus."

    /// A new Itinerary could not be created: nothing is saved yet.
    static func saveFailed(_ error: ItineraryError) -> String {
        let refused = "L'Itinéraire a été refusé par le serveur."
        return failed(error, notSaved: "votre Itinéraire n'est pas encore enregistré.", refused: refused, gone: refused)
    }

    /// An existing Itinerary could not be replaced: it is kept as it was.
    static func updateFailed(_ error: ItineraryError) -> String {
        failed(
            error,
            notSaved: "vos modifications ne sont pas encore enregistrées.",
            refused: "Vos modifications ont été refusées par le serveur.",
            gone: gone
        )
    }

    private static func failed(_ error: ItineraryError, notSaved: String, refused: String, gone: String) -> String {
        switch error {
        case .unavailable: "Altitudes momentanément indisponibles : \(notSaved)"
        case .offline: "Vous êtes hors ligne : \(notSaved)"
        case .network, .server: "Enregistrement impossible pour le moment : \(notSaved)"
        case .unauthorized: sessionExpired
        case .notFound: gone
        case .invalid, .conflict: refused
        }
    }

    static let actions = "Actions"
    static let rename = "Renommer"
    static let renameTitle = "Renommer l'Itinéraire"
    static let namePlaceholder = "Nom"
    static let cancel = "Annuler"
    static let delete = "Supprimer"
    static let deleteTitle = "Supprimer cet Itinéraire ?"
    static let deleteMessage = "Il disparaîtra de tous vos appareils. Cette action est définitive."

    /// A queued change the server turned down (ADR-030 §8).
    static func refused(_ refusal: ItineraryChangeRefusal) -> String {
        switch refusal {
        case .rename: "Renommage refusé par le serveur : le nom précédent est rétabli."
        case .delete: "Suppression refusée par le serveur : l'Itinéraire est rétabli."
        }
    }

    /// The sign-out confirmation, when changes have not been sent yet; nil when none.
    static func signOutWarning(pendingChanges: Int) -> String? {
        switch pendingChanges {
        case ...0: nil
        case 1: "1 modification d'Itinéraire n'a pas encore été envoyée : elle sera perdue."
        default: "\(pendingChanges) modifications d'Itinéraires n'ont pas encore été envoyées : elles seront perdues."
        }
    }

    static let edit = "Modifier"

    /// Why "Modifier" could not reopen the editor.
    static func editUnavailable(_ error: ItineraryError) -> String {
        switch error {
        case .offline: connectionRequired
        case .notFound: gone
        case .unauthorized: sessionExpired
        case .network, .server, .unavailable, .invalid, .conflict: "Chargement de l'Itinéraire impossible pour le moment."
        }
    }

    static func syncFailed(_ error: ItineraryError) -> String {
        error == .offline ? offline : syncFailed
    }
}
