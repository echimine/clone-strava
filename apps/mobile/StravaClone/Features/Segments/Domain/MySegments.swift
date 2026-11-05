import Foundation

/// One of my starred Segments, in Plus › « Segments » (ADR-039 §15).
struct StarredSegment: Identifiable, Equatable, Sendable {
    let id: String
    let sport: SegmentSport
    let name: String
    let isVerified: Bool
    let distance: Distance
    /// Percent.
    let averageGrade: Double
    let climbCategory: ClimbCategory?
    /// My fastest Effort, whatever its visibility; nil without any.
    let myBestTime: Duration?
}

struct StarredSegmentsPage: Equatable, Sendable {
    let items: [StarredSegment]
    let nextCursor: String?
}

enum StarredSegmentsError: Error, Equatable, Sendable {
    case offline
    case unavailable
}

/// `GET /v1/me/segment-favorites` (ADR-039 §12), most recently starred first.
protocol StarredSegmentsRepository: Sendable {
    func page(after cursor: String?) async throws(StarredSegmentsError) -> StarredSegmentsPage
}
