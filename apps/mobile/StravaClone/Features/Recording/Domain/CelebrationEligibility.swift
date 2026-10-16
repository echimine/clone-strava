import Foundation

/// Whether the finish screen opens with the celebration (ADR-032 §5): a Recording of at least
/// 500 m and 2 min, with a trace of at least 2 points. Below, the finish screen shows at once.
/// The thresholds are to be tuned after real outings; they are separate from the sport's
/// `minimumDuration`, which only gates Save.
enum CelebrationEligibility {
    static let minimumDistance = Distance(meters: 500)
    static let minimumDuration = Duration.seconds(120)

    /// `elapsed` is the timer (Pauses excluded), the "Temps" shown on the finish screen.
    static func allows(distance: Distance, elapsed: Duration, pointCount: Int) -> Bool {
        distance >= minimumDistance && elapsed >= minimumDuration && pointCount >= 2
    }

    /// The finished Recording, with the points of its drawn trace.
    static func allows(_ snapshot: RecordingSnapshot) -> Bool {
        let stats = snapshot.finalStats
        return allows(distance: stats.distance, elapsed: stats.elapsed, pointCount: snapshot.trace.count)
    }
}
