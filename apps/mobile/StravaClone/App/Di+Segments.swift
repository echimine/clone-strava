import Foundation

/// Segments (ADR-039 §15): the Map tab's Segments mode.
extension Di {
    /// One for the Map tab, kept across mode switches.
    func makeSegmentMapStore() -> SegmentMapStore {
        SegmentMapStore(
            repository: APISegmentMapRepository(apiClient: apiClient),
            favorites: APISegmentFavoriteRepository(apiClient: apiClient),
            analytics: analytics
        )
    }
}
