import SwiftUI

/// French formats and colours of the Live Activity (ADR-031 §9), the same as the Recording
/// screen: "12,34 km", "5:12 /km", "24,3 km/h".
enum LiveActivityFormat {
    static let accent = Color(red: 0.99, green: 0.32, blue: 0.0)
    static let pause = Color.yellow
    static let dash = "–"
    private static let locale = Locale(identifier: "fr_FR")

    /// "12,34", truncated: never more than was covered.
    static func kilometers(_ meters: Double) -> String {
        let hundredths = Double(Int(max(0, meters) / 10)) / 100
        return hundredths.formatted(.number.precision(.fractionLength(2)).locale(locale))
    }

    /// "12,3", truncated, for the compact island.
    static func kilometersShort(_ meters: Double) -> String {
        let tenths = Double(Int(max(0, meters) / 100)) / 10
        return tenths.formatted(.number.precision(.fractionLength(1)).locale(locale))
    }

    /// "0,75", rounded: a distance left is not a distance covered.
    static func remaining(_ meters: Double) -> String {
        (max(0, meters) / 1_000).formatted(.number.precision(.fractionLength(2)).locale(locale))
    }

    static func pace(_ seconds: Int?) -> String {
        guard let seconds else { return dash }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static func speed(_ kmh: Double?) -> String {
        guard let kmh else { return dash }
        return kmh.formatted(.number.precision(.fractionLength(1)).locale(locale))
    }

    /// "1:05:12" or "5:12".
    static func duration(_ seconds: Int) -> String {
        let h = seconds / 3_600, m = (seconds % 3_600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// The state that replaces "Restant sur l'Itinéraire" off the track and at the end.
    static func itineraryCaption(_ state: RecordingActivityAttributes.ItineraryState) -> String {
        switch state {
        case .notSnapped, .onTrack: "Restant sur l'Itinéraire"
        case .offTrack: "Hors Itinéraire"
        case .finished: "Itinéraire terminé"
        }
    }

    static func remainingText(_ itinerary: RecordingActivityAttributes.Itinerary) -> String {
        itinerary.remainingM.map { "\(remaining($0)) km" } ?? "—"
    }
}

/// Average pace on foot, current speed on a bike.
struct LiveActivitySportStat {
    let label: String
    let value: String
    let unit: String

    init(attributes: RecordingActivityAttributes, state: RecordingActivityAttributes.ContentState, average: Bool = false) {
        if attributes.showsPace {
            label = "Allure moy."
            value = LiveActivityFormat.pace(state.averagePaceS)
            unit = "/km"
        } else {
            label = average ? "Vitesse moy." : "Vitesse"
            value = LiveActivityFormat.speed(average ? state.averageSpeedKmh : state.currentSpeedKmh)
            unit = "km/h"
        }
    }
}
