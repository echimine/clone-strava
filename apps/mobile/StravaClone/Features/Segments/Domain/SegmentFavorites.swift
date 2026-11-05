import Foundation

/// `PUT` / `DELETE /v1/segments/:id/favorite` (ADR-039 §5), idempotent. Minimal version written
/// by #250 for the Map card's star, with #249's signature; #249 owns it.
protocol SegmentFavoriteRepository: Sendable {
    func setFavorite(_ segmentID: String, _ isFavorite: Bool) async throws
}
