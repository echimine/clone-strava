import Foundation

/// The finished trace as the celebration map plays it (ADR-032 §5): where the trace's head is
/// at a given draw progress, and how the camera follows it. Progress is a share of the trace's
/// length on the Web Mercator map, the measure of the map line's trim (`line-progress`), so the
/// head sits at the drawn tip. Display framing, so in Presentation (ADR-007), but pure and
/// independent of Mapbox (ADR-007 rule 6).
struct CelebrationRoute: Sendable {
    /// Turns smaller than this share of the outing's extent leave the camera path.
    static let cameraTolerance = 0.05

    let trace: [Coordinate]
    /// The trace simplified for the camera (Douglas-Peucker): its start, finish and real turns,
    /// without the GPS wiggles that would shake a camera following the head.
    let cameraPath: [Coordinate]
    private let line: MercatorLine
    /// The indices in `trace` of the camera path's points.
    private let cameraIndices: [Int]

    init(trace: [Coordinate]) {
        self.trace = trace
        line = MercatorLine(trace)
        cameraIndices = line.simplified(tolerance: line.extent * Self.cameraTolerance)
        cameraPath = cameraIndices.map { trace[$0] }
    }

    /// The tip of the drawn trace at `progress` (0...1, clamped). Nil without any point.
    func head(at progress: Double) -> Coordinate? {
        line.position(at: progress).map { MercatorLine.unproject($0.point) }
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

    /// Where the camera looks at `progress`: the head brought onto the simplified path's leg
    /// that straightens the head's stretch of trace. It stays within the simplification's
    /// tolerance of the head, wiggles or not, and meets it at each of the path's turns, so it
    /// never jumps from one leg to the next.
    func cameraCenter(at progress: Double) -> Coordinate? {
        guard let head = line.position(at: progress) else { return nil }
        guard let legEnd = cameraIndices.firstIndex(where: { $0 >= head.segmentEnd }), legEnd > 0 else {
            return MercatorLine.unproject(head.point)
        }
        let onLeg = MercatorLine.projection(
            of: head.point,
            ontoSegment: line.points[cameraIndices[legEnd - 1]],
            line.points[cameraIndices[legEnd]]
        )
        return MercatorLine.unproject(onLeg)
    }
}
