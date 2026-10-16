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
