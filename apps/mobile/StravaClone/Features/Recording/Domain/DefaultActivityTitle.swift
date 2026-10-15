import Foundation

/// Title prefilled on the finish screen (ADR-031 §11): the server's formula
/// (`packages/core/.../default-title.ts`), sport and time of day, read at the phone's local
/// time at Start.
enum DefaultActivityTitle {
    /// `title` of `POST /v1/activities`: 1 to 255 characters.
    static let maxLength = 255

    static func make(sport: RecordingSport, startedAt: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let hour = calendar.component(.hour, from: startedAt)
        let label = label(sport)
        switch hour {
        case 5 ..< 12: return "\(label) le matin"
        case 12 ..< 18: return "\(label) l'après-midi"
        case 18 ..< 22: return "\(label) le soir"
        default: return "\(label) de nuit"
        }
    }

    /// The title sent on Save: the athlete's, trimmed and cut to the API's limit, or the
    /// default one when left empty.
    static func resolve(_ title: String, sport: RecordingSport, startedAt: Date, timeZone: TimeZone = .current) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return make(sport: sport, startedAt: startedAt, timeZone: timeZone) }
        return String(trimmed.prefix(maxLength))
    }

    private static func label(_ sport: RecordingSport) -> String {
        switch sport {
        case .run: "Course à pied"
        case .ride: "Sortie à vélo"
        case .walk: "Marche"
        case .hike: "Randonnée"
        }
    }
}
