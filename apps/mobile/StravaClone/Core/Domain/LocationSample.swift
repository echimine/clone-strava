import Foundation

/// One GPS fix, in domain types only (no Core Location).
struct LocationSample: Equatable, Sendable {
    let coordinate: Coordinate
    let altitude: Double?
    let horizontalAccuracy: Double
    /// Direction of travel in degrees from true north, `nil` when unknown.
    var course: Double?
    let timestamp: Date

    init(coordinate: Coordinate, altitude: Double?, horizontalAccuracy: Double, course: Double? = nil, timestamp: Date) {
        self.coordinate = coordinate
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.course = course
        self.timestamp = timestamp
    }
}
