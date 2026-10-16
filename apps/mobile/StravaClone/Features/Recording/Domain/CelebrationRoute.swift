import Foundation

/// The finished trace as the celebration map plays it (ADR-032 §5): where the trace's head is
/// at a given draw progress. Progress is a share of the trace's length on the Web Mercator map,
/// the measure of the map line's trim (`line-progress`), so the head sits at the drawn tip.
/// Pure and independent of Mapbox (ADR-007 rule 6).
struct CelebrationRoute: Sendable {
    /// Turns smaller than this share of the outing's extent leave the camera path.
    static let cameraTolerance = 0.05

    let trace: [Coordinate]
    /// The trace simplified for the camera (Douglas-Peucker): its start, finish and real turns,
    /// without the GPS wiggles that would shake a camera following the head.
    let cameraPath: [Coordinate]
    private let line: MercatorLine
    private let cameraLine: MercatorLine

    init(trace: [Coordinate]) {
        self.trace = trace
        line = MercatorLine(trace)
        let kept = line.simplified(tolerance: line.extent * Self.cameraTolerance)
        cameraPath = kept.map { trace[$0] }
        cameraLine = MercatorLine(cameraPath)
    }

    /// The tip of the drawn trace at `progress` (0...1, clamped). Nil without any point.
    func head(at progress: Double) -> Coordinate? {
        line.coordinate(at: progress)
    }

    /// Zoom levels the follow camera stays within: from a whole region down to a neighbourhood.
    /// Closer, a pitched camera ends up behind the slopes of a valley and loses the trace.
    static let followZooms = 10.0...15.0
    /// While it follows the head, the camera shows this share of the outing's extent across a
    /// phone-wide view, so the head moves at a readable pace whatever the distance.
    static let followShare = 0.8
    private static let viewWidth = 390.0
    /// Map points across the world at zoom 0 (Mapbox's 512-point tiles).
    private static let worldSize = 512.0

    /// The follow camera's zoom (ADR-032 §5): `followShare` of the outing across the view.
    var followZoom: Double {
        let extent = line.extent * Self.followShare
        guard extent > 0 else { return Self.followZooms.upperBound }
        let zoom = log2(Self.viewWidth / (Self.worldSize * extent))
        return min(max(zoom, Self.followZooms.lowerBound), Self.followZooms.upperBound)
    }

    /// Where the camera looks at `progress`: the same share of the simplified path, so it
    /// stays close to the head without its wiggles.
    func cameraCenter(at progress: Double) -> Coordinate? {
        cameraLine.coordinate(at: progress)
    }
}

/// A polyline in Web Mercator units (the world is 1 × 1) with its cumulative length.
private struct MercatorLine: Sendable {
    let points: [(x: Double, y: Double)]
    let cumulative: [Double]

    init(_ coordinates: [Coordinate]) {
        points = coordinates.map(Self.project)
        var cumulative = [0.0]
        for (from, to) in zip(points, points.dropFirst()) {
            cumulative.append(cumulative[cumulative.count - 1] + hypot(to.x - from.x, to.y - from.y))
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

    private static func distance(_ p: (x: Double, y: Double), toSegment a: (x: Double, y: Double), _ b: (x: Double, y: Double)) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let squared = dx * dx + dy * dy
        let t = squared > 0 ? min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / squared, 0), 1) : 0
        return hypot(p.x - (a.x + dx * t), p.y - (a.y + dy * t))
    }

    func coordinate(at progress: Double) -> Coordinate? {
        guard let first = points.first else { return nil }
        guard points.count >= 2, length > 0 else { return Self.unproject(first) }
        let along = min(max(progress, 0), 1) * length
        let segment = (1..<points.count).first(where: { cumulative[$0] >= along }) ?? points.count - 1
        let from = points[segment - 1]
        let to = points[segment]
        let segmentLength = cumulative[segment] - cumulative[segment - 1]
        let t = segmentLength > 0 ? (along - cumulative[segment - 1]) / segmentLength : 0
        return Self.unproject((from.x + (to.x - from.x) * t, from.y + (to.y - from.y) * t))
    }

    static func project(_ coordinate: Coordinate) -> (x: Double, y: Double) {
        let latitude = min(max(coordinate.latitude, -85.051_128_78), 85.051_128_78) * .pi / 180
        return (
            (coordinate.longitude + 180) / 360,
            (1 - log(tan(.pi / 4 + latitude / 2)) / .pi) / 2
        )
    }

    static func unproject(_ point: (x: Double, y: Double)) -> Coordinate {
        Coordinate(
            latitude: atan(sinh(.pi * (1 - 2 * point.y))) * 180 / .pi,
            longitude: point.x * 360 - 180
        )
    }
}
