import Foundation

/// One of my favourite Segments, in Plus › « Segments » (ADR-039 §15).
struct FavoriteSegment: Identifiable, Equatable, Sendable {
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

struct FavoriteSegmentsPage: Equatable, Sendable {
    let items: [FavoriteSegment]
    let nextCursor: String?
}

/// `GET /v1/me/segment-favorites` (ADR-039 §12), most recently added first.
protocol FavoriteSegmentsRepository: Sendable {
    func page(after cursor: String?) async throws(SegmentError) -> FavoriteSegmentsPage
}
