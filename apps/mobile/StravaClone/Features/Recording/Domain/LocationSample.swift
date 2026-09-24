import Foundation

/// One GPS fix, in domain types only (no Core Location).
struct LocationSample: Equatable, Sendable {
    let coordinate: Coordinate
    let altitude: Double?
    let horizontalAccuracy: Double
    let timestamp: Date
}
