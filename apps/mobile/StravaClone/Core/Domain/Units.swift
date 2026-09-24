import Foundation

/// Distance in meters, the unit used by the API.
struct Distance: Hashable, Comparable, Codable, Sendable {
    let meters: Double

    static let zero = Distance(meters: 0)

    var kilometers: Double { meters / 1_000 }

    static func + (lhs: Distance, rhs: Distance) -> Distance {
        Distance(meters: lhs.meters + rhs.meters)
    }

    static func < (lhs: Distance, rhs: Distance) -> Bool {
        lhs.meters < rhs.meters
    }
}

/// Pace in seconds per kilometer; nil when no distance was covered.
func pace(distance: Distance, duration: Duration) -> Duration? {
    guard distance.meters > 0 else { return nil }
    return duration / distance.kilometers
}
