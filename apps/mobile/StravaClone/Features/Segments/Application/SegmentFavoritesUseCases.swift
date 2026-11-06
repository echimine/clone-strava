import Foundation

/// Adds a Segment to my favourites or takes it out (`PUT` / `DELETE /v1/segments/:id/favorite`,
/// ADR-039 §5), idempotent: the star of a Map card and of a sheet.
struct SetSegmentFavorite: Sendable {
    let repository: any SegmentRepository

    func callAsFunction(_ segmentID: String, _ isFavorite: Bool) async throws(SegmentError) {
        try await repository.setFavorite(id: segmentID, isFavorite)
    }
}

/// One page of Plus › « Segments », most recently added first (`GET /v1/me/segment-favorites`).
struct LoadFavoriteSegments: Sendable {
    let repository: any FavoriteSegmentsRepository

    func callAsFunction(after cursor: String?) async throws(SegmentError) -> FavoriteSegmentsPage {
        try await repository.page(after: cursor)
    }
}
