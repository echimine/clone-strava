import Foundation

/// Wording of the Map's Segments mode (ADR-039 §15).
enum SegmentMapMessages {
    static let zoomIn = "Zoome pour voir les Segments"
    static let searchHere = "Rechercher dans cette zone"
    static let noSegment = "Aucun Segment dans cette zone. Crée le premier !"
    static let noFavorite = "Aucun Segment favori dans cette zone."
    static let connectionRequired = "Connexion requise"
    static let searchFailed = "Impossible de charger les Segments."
    static let favoriteFailed = "Le favori n'a pas pu être enregistré."
    static let all = "Tous"
    static let favorites = "Favoris"
    static let verified = "Segment vérifié"

    /// « 1 Segment dans cette zone », « 12 Segments dans cette zone ».
    static func count(_ count: Int) -> String {
        "\(count) Segment\(count > 1 ? "s" : "") dans cette zone"
    }

    /// The chip of a sport: « Vélo », « Course », « Marche », « Randonnée ».
    static func chip(_ sport: SegmentSport) -> String {
        switch sport {
        case .ride: "Vélo"
        case .run: "Course"
        case .walk: "Marche"
        case .hike: "Randonnée"
        }
    }

    /// « 1 athlète », « 1 234 athlètes ».
    static func athletes(_ count: Int) -> String {
        "\(count.formatted(.number.locale(ActivityFormatters.locale))) athlète\(count > 1 ? "s" : "")"
    }

    /// « 7,4 % ».
    static func grade(_ percent: Double) -> String {
        "\(percent.formatted(.number.precision(.fractionLength(1)).locale(ActivityFormatters.locale))) %"
    }

    /// An Effort's time as Strava shows it: « 12:34 », « 1:02:03 », « 45 s ».
    static func time(_ duration: Duration) -> String {
        let total = Int(duration.components.seconds)
        let (hours, minutes, seconds) = (total / 3_600, (total % 3_600) / 60, total % 60)
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        if minutes > 0 { return String(format: "%d:%02d", minutes, seconds) }
        return "\(seconds) s"
    }

    /// « Mon record 12:34 », else « 1er : 11:02 », else nothing.
    static func bestTime(_ segment: MapSegment) -> String? {
        if let mine = segment.myBestTime { return "Mon record \(time(mine))" }
        if let leader = segment.leaderTime { return "1er : \(time(leader))" }
        return nil
    }

    /// « 6,8 km · 7,4 % · Cat. 2 ».
    static func figures(_ segment: MapSegment) -> String {
        ([ActivityFormatters.distance(segment.distance), grade(segment.averageGradePct)] + [segment.climbCategory?.label].compactMap { $0 })
            .joined(separator: " · ")
    }
}
