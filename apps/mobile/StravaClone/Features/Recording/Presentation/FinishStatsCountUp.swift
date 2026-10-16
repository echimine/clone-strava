import Foundation

/// The finish screen's stats (ADR-031 §11) as they count up during the celebration (ADR-032 §5):
/// each value is `progress` of its final value, in the formats of the Recording screen. At 1, the
/// exact final values. The current speed is not a finish stat.
enum FinishStatsCountUp {
    static func items(_ stats: RecordingStats, progress: Double) -> [RecordingStatItem] {
        let final = RecordingFormatters.items(stats).filter { $0.stat != .currentSpeed }
        guard progress < 1 else { return final }
        let fraction = max(0, progress)
        return final.map { item in
            let value = counting(item.stat, stats, fraction) ?? item.value
            return RecordingStatItem(stat: item.stat, label: item.label, value: value, unit: item.unit)
        }
    }

    /// `stat` at `fraction` of its final value; nil for a stat that does not count up.
    private static func counting(_ stat: RecordingStat, _ stats: RecordingStats, _ fraction: Double) -> String? {
        switch stat {
        case .elapsed: RecordingFormatters.timer(scaled(stats.elapsed, by: fraction))
        case .distance: RecordingFormatters.distance(Distance(meters: stats.distance.meters * fraction))
        case .averagePace: RecordingFormatters.pace(stats.averagePace.map { scaled($0, by: fraction) })
        case .averageSpeed: RecordingFormatters.speed(stats.averageSpeedMs * fraction)
        case .currentSpeed, .itineraryRemaining: nil
        }
    }

    private static func scaled(_ duration: Duration, by fraction: Double) -> Duration {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        return .milliseconds(Int64((seconds * fraction * 1_000).rounded(.down)))
    }
}
