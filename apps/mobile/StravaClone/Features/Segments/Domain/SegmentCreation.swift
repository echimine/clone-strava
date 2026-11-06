import Foundation

/// The path being drawn in the Itinerary editor (ADR-039 §15), as the app shell reads it.
struct SegmentDrawing: Equatable, Sendable {
    enum Path: Equatable, Sendable {
        /// No start and finish yet.
        case empty
        /// A gesture is in progress, or a Leg is still being routed.
        case changing
        /// Every Leg routed: the path the server is sent.
        case settled([Coordinate])
    }

    let path: Path
    /// Length as drawn now, measured locally.
    let distance: Distance

    static let empty = SegmentDrawing(path: .empty, distance: .zero)
}

/// A Segment named in an answer: the duplicate of a preview, a created Segment.
struct SegmentRef: Hashable, Sendable {
    let id: String
    let name: String
}

/// Computed by the server from the `ElevationService` (ADR-039 §5); grades in percent.
struct SegmentFigures: Hashable, Sendable {
    let distance: Distance
    let elevationGain: Double
    let averageGrade: Double
    let maxGrade: Double
    let lowestAltitude: Double
    let highestAltitude: Double
    let climbCategory: ClimbCategory?
}

/// `POST /v1/segments/preview`: what a creation would store, and what would refuse it.
struct SegmentPreview: Hashable, Sendable {
    let figures: SegmentFigures
    /// The resampled path (every ~20 m) and its altitudes, one per point.
    let track: [Coordinate]
    let altitudes: [Double]
    let violations: [SegmentRuleViolation]
    /// An existing Segment of the same sport matching it both ways.
    let duplicate: SegmentRef?
    /// Creations left over the rolling 24 h.
    let quotaLeft: Int

    var profile: ElevationProfile {
        ElevationProfile(coordinates: track, altitudes: altitudes)
    }
}

/// A drawn path the server previewed: what « Continuer » opens, what « Créer » sends.
struct SegmentCandidate: Hashable, Sendable {
    let sport: SegmentSport
    /// As drawn: the server resamples it again on creation.
    let points: [Coordinate]
    let preview: SegmentPreview
}

/// `POST /v1/segments/preview` and `POST /v1/segments` (ADR-039 §12).
protocol SegmentCreationRepository: Sendable {
    func preview(sport: SegmentSport, points: [Coordinate]) async throws(SegmentError) -> SegmentPreview
    func create(sport: SegmentSport, name: String, points: [Coordinate]) async throws(SegmentError) -> SegmentRef
}
