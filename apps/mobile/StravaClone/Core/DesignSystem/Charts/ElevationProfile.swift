import Foundation

/// Altitude against the distance covered, drawn in an Itinerary's detail (ADR-030 §3) from
/// the stored track: no network call, so it shows offline.
struct ElevationProfile: Equatable, Sendable {
    struct Point: Equatable, Sendable {
        /// Covered from the start, along the track.
        let distance: Distance
        let altitude: Double
    }

    let points: [Point]

    /// Lowest to highest altitude; nil without any point.
    var altitudeRange: ClosedRange<Double>? {
        guard let low = points.map(\.altitude).min(), let high = points.map(\.altitude).max() else { return nil }
        return low...high
    }
}

extension ItineraryTrack {
    /// One point per altitude (a point of the track without one is left out), thinned to at
    /// most `maxPoints` for drawing: the ends are kept, and each stretch keeps its lowest and
    /// highest point so that no summit or valley disappears.
    func elevationProfile(maxPoints: Int = 400) -> ElevationProfile {
        let coordinates = polyline.decode()
        let count = min(coordinates.count, altitudes.count)
        guard count > 0 else { return ElevationProfile(points: []) }

        var points: [ElevationProfile.Point] = []
        points.reserveCapacity(count)
        var covered = Distance.zero
        for index in 0..<count {
            if index > 0 {
                covered = covered + coordinates[index - 1].distance(to: coordinates[index])
            }
            points.append(ElevationProfile.Point(distance: covered, altitude: altitudes[index]))
        }
        return ElevationProfile(points: Self.thin(points, to: max(maxPoints, 4)))
    }

    private static func thin(_ points: [ElevationProfile.Point], to maxPoints: Int) -> [ElevationProfile.Point] {
        guard points.count > maxPoints else { return points }
        let interior = points[1..<(points.count - 1)]
        let buckets = (maxPoints - 2) / 2
        let size = Double(interior.count) / Double(buckets)
        var kept = [points[0]]
        for bucket in 0..<buckets {
            let lower = interior.startIndex + Int((Double(bucket) * size).rounded(.down))
            let upper = min(interior.startIndex + Int((Double(bucket + 1) * size).rounded(.down)), interior.endIndex)
            guard lower < upper else { continue }
            let stretch = interior[lower..<upper]
            let low = stretch.indices.min { stretch[$0].altitude < stretch[$1].altitude }!
            let high = stretch.indices.max { stretch[$0].altitude < stretch[$1].altitude }!
            kept += Set([low, high]).sorted().map { points[$0] }
        }
        kept.append(points[points.count - 1])
        return kept
    }
}
