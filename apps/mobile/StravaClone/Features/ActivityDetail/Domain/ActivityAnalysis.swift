import Foundation

/// How an Activity came in (ADR-036 §6, §9): recorded in the app, imported from a file, or
/// entered by hand.
enum ActivitySource: String, Hashable, Sendable {
    case recorded
    case imported
    case manual
}

/// The Activity analysis the worker derives from the cleaned trace (ADR-036 §6): the
/// kilometre splits and the series the charts draw. No coordinates.
struct ActivityAnalysis: Hashable, Sendable {
    /// One per 1,000 m, the last one covering the rest; empty without a usable GPS trace.
    let splits: [ActivitySplit]
    /// Nil without a usable GPS trace.
    let series: ActivitySeries?
}

/// One kilometre, or the rest of the distance for the last one (ADR-036 §6).
struct ActivitySplit: Hashable, Sendable {
    let distance: Distance
    let movingTime: Duration
    /// Altitude at its end minus altitude at its start; nil without elevation.
    let elevationDiff: Double?
    let avgHeartRate: Int?

    /// Nil when no moving time was counted.
    var speedMs: Double? {
        let seconds = Double(movingTime.components.seconds)
        return seconds > 0 ? distance.meters / seconds : nil
    }
}

/// At most 300 samples evenly spaced along the distance (ADR-036 §6). The arrays have the
/// same length; speed is 0 during stops.
struct ActivitySeries: Hashable, Sendable {
    let distanceM: [Double]
    let speedMs: [Double]
    /// Nil when no point has an elevation.
    let altitudeM: [Double]?
    /// Nil when no point has a heart rate.
    let heartRateBpm: [Int]?
}
