import Foundation

/// A point in Web Mercator units: the world is 1 × 1, x eastward from 180° W, y southward from
/// the top of the map.
struct MercatorPoint: Equatable, Sendable {
    let x: Double
    let y: Double

    func distance(to other: MercatorPoint) -> Double {
        hypot(other.x - x, other.y - y)
    }
}

/// A polyline in Web Mercator units with its cumulative length (the celebration's trace).
struct MercatorLine: Sendable {
    let points: [MercatorPoint]
    let cumulative: [Double]

    init(_ coordinates: [Coordinate]) {
        points = coordinates.map(Self.project)
        var cumulative = [0.0]
        for (from, to) in zip(points, points.dropFirst()) {
            cumulative.append(cumulative[cumulative.count - 1] + from.distance(to: to))
        }
        self.cumulative = cumulative
    }

    var length: Double { cumulative.last ?? 0 }

    /// The diagonal of the bounding box.
    var extent: Double {
        guard let first = points.first else { return 0 }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        return hypot(maxX - minX, maxY - minY)
    }

    /// Indices kept by Douglas-Peucker: every point farther than `tolerance` from the segment
    /// between kept neighbours, plus the first and last. Iterative, for long traces.
    func simplified(tolerance: Double) -> [Int] {
        guard points.count > 2 else { return Array(points.indices) }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var ranges = [(0, points.count - 1)]
        while let (start, end) = ranges.popLast() {
            guard end - start > 1 else { continue }
            var farthest = start, distance = 0.0
            for index in (start + 1)..<end {
                let candidate = Self.distance(points[index], toSegment: points[start], points[end])
                if candidate > distance {
                    farthest = index
                    distance = candidate
                }
            }
            if distance > tolerance {
                keep[farthest] = true
                ranges.append((start, farthest))
                ranges.append((farthest, end))
            }
        }
        return keep.indices.filter { keep[$0] }
    }

    private static func distance(_ p: MercatorPoint, toSegment a: MercatorPoint, _ b: MercatorPoint) -> Double {
        p.distance(to: projection(of: p, ontoSegment: a, b))
    }

    /// The point of the segment `a`–`b` closest to `p`.
    static func projection(of p: MercatorPoint, ontoSegment a: MercatorPoint, _ b: MercatorPoint) -> MercatorPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        let squared = dx * dx + dy * dy
        let t = squared > 0 ? min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / squared, 0), 1) : 0
        return MercatorPoint(x: a.x + dx * t, y: a.y + dy * t)
    }

    /// The point at `progress` (0...1, clamped) of the length, and the index of the point that
    /// ends its segment. Nil without any point; the only point, at index 0, without a length.
    func position(at progress: Double) -> (point: MercatorPoint, segmentEnd: Int)? {
        guard let first = points.first else { return nil }
        guard points.count >= 2, length > 0 else { return (first, 0) }
        let along = min(max(progress, 0), 1) * length
        let segment = (1..<points.count).first(where: { cumulative[$0] >= along }) ?? points.count - 1
        let from = points[segment - 1]
        let to = points[segment]
        let segmentLength = cumulative[segment] - cumulative[segment - 1]
        let t = segmentLength > 0 ? (along - cumulative[segment - 1]) / segmentLength : 0
        return (MercatorPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t), segment)
    }

    static func project(_ coordinate: Coordinate) -> MercatorPoint {
        let latitude = min(max(coordinate.latitude, -85.051_128_78), 85.051_128_78) * .pi / 180
        return MercatorPoint(
            x: (coordinate.longitude + 180) / 360,
            y: (1 - log(tan(.pi / 4 + latitude / 2)) / .pi) / 2
        )
    }

    static func unproject(_ point: MercatorPoint) -> Coordinate {
        Coordinate(
            latitude: atan(sinh(.pi * (1 - 2 * point.y))) * 180 / .pi,
            longitude: point.x * 360 - 180
        )
    }
}
