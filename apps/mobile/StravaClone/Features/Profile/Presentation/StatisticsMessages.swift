import Foundation

/// French strings of the Progrès tab and the Statistiques screen (ADR-036 §4).
enum StatisticsMessages {
    static let title = "Statistiques"
    static let errorTitle = "Statistiques indisponibles"
    static let progressErrorTitle = "Progrès indisponibles"
    static let recentTitle = "ACTIVITÉ"
    static let yearToDateTitle = "DEPUIS LE DÉBUT DE L'ANNÉE"
    static let allTimeTitle = "DE TOUT TEMPS"
    static let recentFooter = "Moyenne des 4 dernières semaines complètes."
    static let time = "Temps"
    static let distance = "Distance"
    static let elevation = "Dénivelé"
    static let thisWeek = "Cette semaine"
    static let lastTwelveWeeks = "12 dernières semaines"
    static let streak = "Série"
    static let sportPicker = "Sport"

    /// The number of outings, as the sport names them.
    static func outings(_ sport: SportType?) -> String {
        switch sport {
        case .run: "Courses"
        case .ride: "Sorties à vélo"
        case .swim: "Séances de natation"
        case .walk: "Marches"
        case .hike: "Randonnées"
        case .other, nil: "Activités"
        }
    }

    static func perWeek(_ label: String) -> String {
        "\(label) par semaine"
    }

    /// "1,5": an average number of outings.
    static func average(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(ActivityFormatters.locale))
    }

    /// "5 semaines" of Série.
    static func streakWeeks(_ weeks: Int) -> String {
        weeks == 1 ? "1 semaine" : "\(weeks) semaines"
    }

    /// "Semaine du 3 nov." under the chart, for the chosen week.
    static func weekOf(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = ActivityFormatters.locale
        formatter.timeZone = ProgressCalendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return "Semaine du \(formatter.string(from: date))"
    }

    /// "novembre 2026" over the Série's calendar.
    static func month(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = ActivityFormatters.locale
        formatter.timeZone = ProgressCalendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: date)
    }

    static func message(for error: AthleteError) -> String {
        ProfileMessages.message(for: error)
    }
}
