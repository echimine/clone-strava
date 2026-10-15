import Foundation

/// One stat of the Recording screen: "5:12" with its unit "/km" and label "Allure moy.".
struct RecordingStatItem: Equatable, Identifiable {
    let label: String
    let value: String
    let unit: String
    var id: String { label }
}

/// French display formats of a Recording's live stats (ADR-031 §5): "0,00 km", "h:mm:ss",
/// "5:12 /km", "24,3 km/h". Values without their unit.
enum RecordingFormatters {
    static let dash = "–"

    /// "0:05:12".
    static func timer(_ duration: Duration) -> String {
        let total = max(0, Int(duration.components.seconds))
        return "\(total / 3_600):\(twoDigits((total % 3_600) / 60)):\(twoDigits(total % 60))"
    }

    /// "12,34" (km), truncated: never more than was covered.
    static func distance(_ distance: Distance) -> String {
        let hundredths = Double(Int(max(0, distance.meters) / 10)) / 100
        return hundredths.formatted(.number.precision(.fractionLength(2)).locale(ActivityFormatters.locale))
    }

    /// "5:12" (/km), or "–".
    static func pace(_ pace: Duration?) -> String {
        guard let pace else { return dash }
        let seconds = Int((Double(pace.components.seconds) + Double(pace.components.attoseconds) / 1e18).rounded())
        return "\(seconds / 60):\(twoDigits(seconds % 60))"
    }

    /// "24,3" (km/h) from m/s, or "–".
    static func speed(_ metersPerSecond: Double?) -> String {
        guard let metersPerSecond else { return dash }
        return (metersPerSecond * 3.6).formatted(.number.precision(.fractionLength(1)).locale(ActivityFormatters.locale))
    }

    /// The sport's stats, in display order: pace on foot, speeds on a bike.
    static func items(_ stats: RecordingStats) -> [RecordingStatItem] {
        var items = [
            RecordingStatItem(label: "Temps", value: timer(stats.elapsed), unit: ""),
            RecordingStatItem(label: "Distance", value: distance(stats.distance), unit: "km"),
        ]
        if stats.sport.isOnFoot {
            items.append(RecordingStatItem(label: "Allure moy.", value: pace(stats.averagePace), unit: "/km"))
        } else {
            items.append(RecordingStatItem(label: "Vitesse", value: speed(stats.currentSpeedMs), unit: "km/h"))
            items.append(RecordingStatItem(label: "Vitesse moy.", value: speed(stats.averageSpeedMs), unit: "km/h"))
        }
        return items
    }

    /// Distance left on the followed Itinerary (ADR-031 §6, §8): "—" before the first snap; the
    /// state replaces the "Restant sur l'Itinéraire" label off the track and at the end.
    static func itinerary(_ progress: ItineraryProgress) -> RecordingStatItem {
        let label = switch progress.status {
        case .notSnapped, .onTrack: RecordingMessages.remainingOnItinerary
        case .offTrack: RecordingMessages.offItinerary
        case .finished: RecordingMessages.itineraryFinished
        }
        return RecordingStatItem(label: label, value: progress.remaining.map(remaining) ?? "—", unit: "km")
    }

    /// "0,75" (km), rounded: a distance left is not a distance covered.
    private static func remaining(_ distance: Distance) -> String {
        (max(0, distance.meters) / 1_000).formatted(.number.precision(.fractionLength(2)).locale(ActivityFormatters.locale))
    }

    static func sportLabel(_ sport: RecordingSport) -> String {
        ActivityFormatters.sportLabel(sport.sportType)
    }

    static func sportSymbol(_ sport: RecordingSport) -> String {
        ActivityFormatters.sportSymbol(sport.sportType)
    }

    private static func twoDigits(_ value: Int) -> String {
        String(format: "%02d", value)
    }
}
