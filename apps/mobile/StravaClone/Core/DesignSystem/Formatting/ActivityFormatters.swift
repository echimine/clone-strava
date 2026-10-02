import Foundation

/// French display formats of an activity card (ADR-029). Pure: `now`, calendar and locale
/// are parameters so tests are deterministic.
enum ActivityFormatters {
    static let locale = Locale(identifier: "fr_FR")

    /// "Aujourd'hui à 14:32", "Hier à 08:05", "lundi à 18:10" within the week,
    /// "12 septembre à 14:32" this year, "12 septembre 2025 à 14:32" before.
    static func relativeDateTime(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let time = format(date, "HH:mm", calendar: calendar)
        let startOfToday = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: startOfToday).day ?? 0
        switch days {
        case ..<0:
            return "\(format(date, "d MMMM yyyy", calendar: calendar)) à \(time)"
        case 0:
            return "Aujourd'hui à \(time)"
        case 1:
            return "Hier à \(time)"
        case 2...6:
            return "\(format(date, "EEEE", calendar: calendar)) à \(time)"
        default:
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            return "\(format(date, sameYear ? "d MMMM" : "d MMMM yyyy", calendar: calendar)) à \(time)"
        }
    }

    /// "10,23 km", or "850 m" under a kilometer.
    static func distance(_ distance: Distance) -> String {
        if distance.meters < 1_000 {
            return "\(Int(distance.meters.rounded())) m"
        }
        return "\(distance.kilometers.formatted(.number.precision(.fractionLength(2)).locale(locale))) km"
    }

    /// "245 m".
    static func elevation(_ meters: Double) -> String {
        "\(Int(meters.rounded()).formatted(.number.locale(locale))) m"
    }

    /// "52 min 10 s", or "1 h 05 min" from an hour.
    static func duration(_ duration: Duration) -> String {
        let total = Int(duration.components.seconds)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if hours > 0 {
            return "\(hours) h \(String(format: "%02d", minutes)) min"
        }
        if minutes > 0 {
            return "\(minutes) min \(seconds) s"
        }
        return "\(seconds) s"
    }

    static func sportLabel(_ sport: SportType) -> String {
        switch sport {
        case .run: "Course à pied"
        case .ride: "Vélo"
        case .swim: "Natation"
        case .walk: "Marche"
        case .hike: "Randonnée"
        case .other: "Activité"
        }
    }

    /// SF Symbol of the sport.
    static func sportSymbol(_ sport: SportType) -> String {
        switch sport {
        case .run: "figure.run"
        case .ride: "figure.outdoor.cycle"
        case .swim: "figure.pool.swim"
        case .walk: "figure.walk"
        case .hike: "figure.hiking"
        case .other: "figure.mixed.cardio"
        }
    }

    static func sportEmoji(_ sport: SportType) -> String {
        switch sport {
        case .run: "🏃"
        case .ride: "🚴"
        case .swim: "🏊"
        case .walk: "🚶"
        case .hike: "🥾"
        case .other: "💪"
        }
    }

    /// Text sent to the share sheet: "Sortie du matin · Course à pied de 10,23 km à Annecy 🏃".
    static func shareText(for post: ActivityPost) -> String {
        var summary = sportLabel(post.sport)
        if let distance = post.distance, distance.meters > 0 {
            summary += " de \(Self.distance(distance))"
        }
        if let location = post.locationName {
            summary += " à \(location)"
        }
        return "\(post.title) · \(summary) \(sportEmoji(post.sport))"
    }

    private static func format(_ date: Date, _ template: String, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = template
        return formatter.string(from: date)
    }
}
