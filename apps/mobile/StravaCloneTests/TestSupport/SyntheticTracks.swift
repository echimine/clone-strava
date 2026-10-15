import Foundation
@testable import StravaClone

/// Synthetic Itinerary tracks drawn in meters east and north of an origin, resampled every
/// 20 m like the API's cached tracks (ADR-031 §6).
enum SyntheticTrack {
    static let origin = Coordinate(latitude: 45.764, longitude: 4.8357)

    /// A point `east` and `north` meters from the origin.
    static func point(east: Double, north: Double) -> Coordinate {
        origin.shifted(east: east, north: north)
    }

    /// The straight lines between `corners` (meters east, north), one point every `step` meters.
    static func through(_ corners: [(east: Double, north: Double)], step: Double = 20) -> [Coordinate] {
        guard let first = corners.first else { return [] }
        var points = [point(east: first.east, north: first.north)]
        for (from, to) in zip(corners, corners.dropFirst()) {
            let length = hypot(to.east - from.east, to.north - from.north)
            let count = max(1, Int((length / step).rounded(.up)))
            for index in 1...count {
                let t = Double(index) / Double(count)
                points.append(point(east: from.east + (to.east - from.east) * t, north: from.north + (to.north - from.north) * t))
            }
        }
        return points
    }

    /// Length of the track as the phone measures it.
    static func length(_ points: [Coordinate]) -> Distance {
        zip(points, points.dropFirst()).reduce(.zero) { $0 + $1.0.distance(to: $1.1) }
    }
}

extension Coordinate {
    /// A point `east` and `north` meters away, on the 6,371 km sphere.
    func shifted(east: Double, north: Double) -> Coordinate {
        let radius = 6_371_008.8
        let latitude = latitude + north / radius * 180 / .pi
        let longitude = longitude + east / (radius * cos(self.latitude * .pi / 180)) * 180 / .pi
        return Coordinate(latitude: latitude, longitude: longitude)
    }
}
