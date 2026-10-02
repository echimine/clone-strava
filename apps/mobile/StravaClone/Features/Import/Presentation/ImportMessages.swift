import Foundation

/// French texts of the import (labels and error messages, ADR-028 §7).
enum ImportMessages {
    static func message(forCode code: String?) -> String {
        switch code {
        case "invalid_file": "Le fichier est illisible ou corrompu."
        case "unsupported_format": "Ce format de fichier n'est pas pris en charge."
        case "no_timestamps": "Le fichier ne contient pas d'horodatage : c'est sans doute un itinéraire, pas une activité."
        case "no_gps_data": "Ce fichier ne contient pas de tracé GPS (activité en salle non prise en charge)."
        case "empty_track": "Le fichier ne contient aucun point exploitable."
        case "too_many_points": "Le fichier est trop long pour être importé."
        case "invalid_duration": "L'activité est trop courte pour ce sport."
        case "unknown_sport": "Le sport n'a pas pu être détecté. Choisissez-le pour réessayer."
        case "file_missing": "Le fichier n'a pas pu être envoyé. Réessayez."
        case "file_too_large": "Le fichier dépasse 25 Mo."
        case "rate_limited": "Trop d'imports en peu de temps. Réessayez dans un moment."
        default: "L'import a échoué. Réessayez plus tard."
        }
    }

    static func message(for error: any Error) -> String {
        guard let error = error as? ImportError else { return message(forCode: nil) }
        switch error {
        case .offline: return "Pas de connexion internet."
        case .unsupportedFile: return "Choisissez un fichier .gpx, .tcx ou .fit."
        case .fileTooLarge: return message(forCode: "file_too_large")
        case .unreadableFile: return "Impossible de lire ce fichier."
        case .uploadURLExpired, .network: return "Impossible de joindre le serveur. Réessayez."
        case .rateLimited: return message(forCode: "rate_limited")
        case .unauthorized: return "Session expirée, reconnectez-vous."
        case .server(let code): return message(forCode: code)
        }
    }

    static func label(for sport: ImportSport) -> String {
        switch sport {
        case .run: "Course à pied"
        case .ride: "Vélo"
        case .swim: "Natation"
        case .walk: "Marche"
        case .hike: "Randonnée"
        }
    }

    static func label(for visibility: ImportVisibility) -> String {
        switch visibility {
        case .everyone: "Tout le monde"
        case .followers: "Abonnés"
        case .onlyMe: "Moi uniquement"
        }
    }
}
