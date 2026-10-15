import Foundation

/// A polyline (an Itinerary's track, a Return path) as segments with their cumulative
/// distance, and projections onto it (ADR-031 §6, §7).
struct TrackGeometry: Equatable, Sendable {
    let points: [Coordinate]
    /// Distance from the start to each point.
    let cumulative: [Double]

    init(_ points: [Coordinate]) {
        self.points = points
        var cumulative = [0.0]
        for (from, to) in zip(points, points.dropFirst()) {
            cumulative.append(cumulative[cumulative.count - 1] + from.distance(to: to).meters)
        }
        self.cumulative = cumulative
    }

    var length: Double { cumulative.last ?? 0 }

    private var segmentCount: Int { max(0, points.count - 1) }

    /// The point `along` meters from the start, between the two points around it.
    func coordinate(at along: Double) -> Coordinate? {
        guard let first = points.first else { return nil }
        guard let segment = (0..<segmentCount).first(where: { cumulative[$0 + 1] >= along }) else {
            return points.last
        }
        let from = points[segment]
        let to = points[segment + 1]
        let length = cumulative[segment + 1] - cumulative[segment]
        let t = length > 0 ? min(max((along - cumulative[segment]) / length, 0), 1) : 0
        return segmentCount == 0 ? first : Coordinate(
            latitude: from.latitude + (to.latitude - from.latitude) * t,
            longitude: from.longitude + (to.longitude - from.longitude) * t
        )
    }

    /// The closest point of the track between `range` bounds, then further ahead while it
    /// keeps getting closer (a window never cuts a projection short). Ties go to the earliest.
    func nearest(to position: Coordinate, in range: ClosedRange<Double>) -> (along: Double, distance: Double)? {
        var best: (along: Double, distance: Double, segment: Int)?
        for segment in 0..<segmentCount where cumulative[segment + 1] >= range.lowerBound && cumulative[segment] <= range.upperBound {
            let match = project(position, on: segment, within: range)
            if best == nil || match.distance < best!.distance {
                best = (match.along, match.distance, segment)
            }
        }
        guard let found = best else { return nil }
        return descend(from: found, toward: position)
    }

    /// The first segment in track order, from `along` on, with a point within `radius`, then
    /// the closest point from there on while it keeps getting closer.
    func firstSnap(of position: Coordinate, from along: Double, radius: Double) -> Double? {
        let range = along...length
        for segment in 0..<segmentCount where cumulative[segment + 1] >= along {
            let match = project(position, on: segment, within: range)
            if match.distance <= radius {
                return descend(from: (match.along, match.distance, segment), toward: position).along
            }
        }
        return nil
    }

    private func descend(
        from start: (along: Double, distance: Double, segment: Int),
        toward position: Coordinate
    ) -> (along: Double, distance: Double) {
        var best = start
        var segment = start.segment
        while true {
            let range = best.along...length
            var improved = false
            // The rest of the current segment, then the next ones.
            let current = project(position, on: segment, within: range)
            if current.distance < best.distance - 0.01 {
                best = (current.along, current.distance, segment)
                improved = true
            }
            guard segment + 1 < segmentCount else { break }
            let next = project(position, on: segment + 1, within: range)
            if next.distance < best.distance - 0.01 {
                best = (next.along, next.distance, segment + 1)
                segment += 1
                continue
            }
            if !improved { break }
        }
        return (best.along, best.distance)
    }

    /// The closest point of one segment to `position`, kept between `range` bounds.
    private func project(_ position: Coordinate, on segment: Int, within range: ClosedRange<Double>) -> (along: Double, distance: Double) {
        let from = points[segment]
        let to = points[segment + 1]
        let start = cumulative[segment]
        let length = cumulative[segment + 1] - start
        // Local plane in meters around the segment start: fine for ~20 m segments.
        let metersPerDegreeLat = 111_195.0
        let metersPerDegreeLon = metersPerDegreeLat * cos(from.latitude * .pi / 180)
        let bx = (to.longitude - from.longitude) * metersPerDegreeLon
        let by = (to.latitude - from.latitude) * metersPerDegreeLat
        let px = (position.longitude - from.longitude) * metersPerDegreeLon
        let py = (position.latitude - from.latitude) * metersPerDegreeLat
        let squared = bx * bx + by * by
        var t = squared > 0 ? (px * bx + py * by) / squared : 0
        t = min(max(t, 0), 1)
        if length > 0 {
            let lower = (range.lowerBound - start) / length
            let upper = (range.upperBound - start) / length
            t = min(max(t, max(0, lower)), min(1, max(upper, 0)))
        }
        let dx = px - bx * t
        let dy = py - by * t
        return (start + length * t, (dx * dx + dy * dy).squareRoot())
    }
}
