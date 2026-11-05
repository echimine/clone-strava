import Foundation

/// One Segment of the Map tab (ADR-039 §12, §15): what its card and its path show.
struct MapSegment: Identifiable, Equatable, Sendable {
    let id: String
    let sport: SegmentSport
    let name: String
    let isVerified: Bool
    /// In my favourites.
    var isStarred: Bool
    let distance: Distance
    /// Average grade, in percent.
    let averageGradePct: Double
    let climbCategory: ClimbCategory?
    /// Athletes with at least one Effort on the Leaderboard.
    let athleteCount: Int
    /// My best Effort, all visibilities.
    let myBestTime: Duration?
    /// The 1st of the Leaderboard, only when I have no Effort.
    let leaderTime: Duration?
    let path: [Coordinate]
}

/// The Map's filters (ADR-039 §15): one sport or all, combined with my favourites.
struct SegmentMapFilter: Equatable, Sendable {
    var sport: SegmentSport?
    var favoritesOnly = false
}

enum SegmentMapError: Error, Equatable {
    case offline
    /// The zone is larger than a screen at zoom 10.5 (`400 zone_too_large`).
    case zoneTooLarge
    case failed
}

/// `GET /v1/segments` (ADR-039 §12).
protocol SegmentMapRepository: Sendable {
    /// At most 50 Segments crossing `area`, the most-ridden first.
    func segments(in area: MapArea, filter: SegmentMapFilter) async throws(SegmentMapError) -> [MapSegment]
}
