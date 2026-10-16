import Foundation

/// The finish screen's stats (ADR-031 §11) as they count up during the celebration (ADR-032 §5):
/// each value is `progress` of its final value, in the formats of the Recording screen. At 1, the
/// exact final values. The current speed is not a finish stat.
enum FinishStatsCountUp {
    static func items(_ stats: RecordingStats, progress: Double) -> [RecordingStatItem] {
        let final = RecordingFormatters.items(stats).filter { $0.label != currentSpeedLabel }
        guard progress < 1 else { return final }
        let fraction = max(0, progress)
        let values = [
            RecordingFormatters.timer(scaled(stats.elapsed, by: fraction)),
            RecordingFormatters.distance(Distance(meters: stats.distance.meters * fraction)),
            stats.sport.isOnFoot
                ? RecordingFormatters.pace(stats.averagePace.map { scaled($0, by: fraction) })
                : RecordingFormatters.speed(stats.averageSpeedMs * fraction),
        ]
        return zip(final, values).map { item, value in
            RecordingStatItem(label: item.label, value: value, unit: item.unit)
        }
    }

    private static let currentSpeedLabel = "Vitesse"

    private static func scaled(_ duration: Duration, by fraction: Double) -> Duration {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        return .milliseconds(Int64((seconds * fraction * 1_000).rounded(.down)))
    }
}
