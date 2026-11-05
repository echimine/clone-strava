import Foundation

/// `APIClient` adapter of `SegmentFavoriteRepository` (ADR-039 §5). Minimal version written by
/// #250 for the Map card's star; #249 owns it.
struct APISegmentFavoriteRepository: SegmentFavoriteRepository {
    let apiClient: APIClient

    func setFavorite(_ segmentID: String, _ isFavorite: Bool) async throws {
        let _: NoContent = try await apiClient.send(
            method: isFavorite ? "PUT" : "DELETE",
            path: "/v1/segments/\(segmentID)/favorite"
        )
    }
}
