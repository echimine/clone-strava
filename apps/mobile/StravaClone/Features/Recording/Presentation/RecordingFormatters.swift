import Foundation

/// Which stat a `RecordingStatItem` shows, whatever its French label.
enum RecordingStat: Equatable, Sendable {
    case elapsed, distance, averagePace, currentSpeed, averageSpeed, itineraryRemaining
}

/// One stat of the Recording screen: "5:12" with its unit "/km" and label "Allure moy.".
struct RecordingStatItem: Equatable, Identifiable {
    let stat: RecordingStat
    let label: String
    let value: String
    let unit: String
    var id: String { label }

    /// The label under the value, with its unit: "Distance (km)", or "Temps".
    var caption: String {
        unit.isEmpty ? label : "\(label) (\(unit))"
    }
}

/// French display formats of a Recording's provisional values (ADR-031 §5): "0,00 km", "h:mm:ss",
/// "5:12 /km", "24,3 km/h". Values without their unit.
enum RecordingFormatters {
    static let dash = RecordingNumberFormat.dash

    /// "0:05:12".
    static func timer(_ duration: Duration) -> String {
        let total = max(0, Int(duration.components.seconds))
        return "\(total / 3_600):\(twoDigits((total % 3_600) / 60)):\(twoDigits(total % 60))"
    }

    /// "12,34" (km), truncated: never more than was covered.
    static func distance(_ distance: Distance) -> String {
        RecordingNumberFormat.kilometers(distance.meters)
    }

    /// "5:12" (/km), or "–".
    static func pace(_ pace: Duration?) -> String {
        let seconds = pace.map { Int((Double($0.components.seconds) + Double($0.components.attoseconds) / 1e18).rounded()) }
        return RecordingNumberFormat.pace(seconds: seconds)
    }

    /// "24,3" (km/h) from m/s, or "–".
    static func speed(_ metersPerSecond: Double?) -> String {
        RecordingNumberFormat.speed(kmh: metersPerSecond.map { $0 * 3.6 })
    }

    /// The sport's stats, in display order: pace on foot, speeds on a bike.
    static func items(_ stats: RecordingStats) -> [RecordingStatItem] {
        var items = [
            RecordingStatItem(stat: .elapsed, label: "Temps", value: timer(stats.elapsed), unit: ""),
            RecordingStatItem(stat: .distance, label: "Distance", value: distance(stats.distance), unit: "km"),
        ]
        if stats.sport.isOnFoot {
            items.append(RecordingStatItem(stat: .averagePace, label: "Allure moy.", value: pace(stats.averagePace), unit: "/km"))
        } else {
            items.append(RecordingStatItem(stat: .currentSpeed, label: "Vitesse", value: speed(stats.currentSpeedMs), unit: "km/h"))
            items.append(RecordingStatItem(stat: .averageSpeed, label: "Vitesse moy.", value: speed(stats.averageSpeedMs), unit: "km/h"))
        }
        return items
    }

    /// Distance left on the followed Itinerary (ADR-031 §6, §7, §8): "—" before the first snap;
    /// the state replaces the "Restant sur l'Itinéraire" label off the track, on a Return path
    /// and at the end.
    static func itinerary(_ itinerary: FollowedItinerary) -> RecordingStatItem {
        RecordingStatItem(
            stat: .itineraryRemaining,
            label: itinerary.state.caption,
            value: itinerary.remaining.map { RecordingNumberFormat.remainingKilometers($0.meters) } ?? "—",
            unit: "km"
        )
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
