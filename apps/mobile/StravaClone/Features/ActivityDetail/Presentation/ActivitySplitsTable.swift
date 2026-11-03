import Foundation

/// The rows of "Temps intermédiaires" (ADR-036 §9): Km, Allure (Vitesse for a `speed`
/// sport), a bar proportional to speed, Élév. and FC. The FC column is hidden when no split
/// has a heart rate.
struct ActivitySplitsTable: Hashable {
    struct Row: Hashable, Identifiable {
        let id: Int
        /// "1", "2", … then the rest in kilometres: "0,14".
        let kilometer: String
        /// "5:00 /km" or "36,0 km/h"; "–" without moving time.
        let speed: String
        /// The split's speed over the fastest split's, 0…1.
        let barFraction: Double
        /// "+4 m"; nil without elevation.
        let elevation: String?
        let heartRate: String?
    }

    let rows: [Row]
    let speedTitle: String
    let showsHeartRate: Bool

    /// A last split under this is the rest of the distance, labelled in kilometres.
    static let fullSplitMeters = 995.0

    init(splits: [ActivitySplit], sport: SportType) {
        let pace = sport.paceUnit == .pace
        let fastest = splits.compactMap(\.speedMs).max() ?? 0
        rows = splits.enumerated().map { index, split in
            let isRest = index == splits.count - 1 && split.distance.meters < Self.fullSplitMeters
            let speed = split.speedMs
            return Row(
                id: index,
                kilometer: isRest ? Self.kilometers(split.distance) : "\(index + 1)",
                speed: speed.flatMap { Self.speedText($0, pace: pace) } ?? "–",
                barFraction: fastest > 0 ? (speed ?? 0) / fastest : 0,
                elevation: split.elevationDiff.map(Self.signedElevation),
                heartRate: split.avgHeartRate.map { "\($0)" }
            )
        }
        speedTitle = pace ? ActivityAnalysisMessages.pace : ActivityAnalysisMessages.speed
        showsHeartRate = splits.contains { $0.avgHeartRate != nil }
    }

    /// "5:00 /km" for a `pace` sport, "36,0 km/h" otherwise; nil without movement.
    static func speedText(_ metersPerSecond: Double, pace: Bool) -> String? {
        guard metersPerSecond > 0 else { return nil }
        return pace
            ? ActivityFormatters.pace(metersPerSecond: metersPerSecond)
            : ActivityFormatters.speed(metersPerSecond: metersPerSecond)
    }

    private static func kilometers(_ distance: Distance) -> String {
        distance.kilometers.formatted(.number.precision(.fractionLength(2)).locale(ActivityFormatters.locale))
    }

    private static func signedElevation(_ meters: Double) -> String {
        let rounded = Int(meters.rounded())
        return rounded > 0 ? "+\(rounded) m" : "\(rounded) m"
    }
}
