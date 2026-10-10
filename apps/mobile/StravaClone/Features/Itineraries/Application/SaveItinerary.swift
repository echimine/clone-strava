import Foundation

/// Saves a new Itinerary (ADR-030 §6, §8): `POST` under the app-generated id, so a replay
/// never duplicates it, then the detail is written straight to the cache and the
/// Itinerary is listed at once. On failure nothing is written and the editor keeps its draft.
struct SaveItinerary: Sendable {
    let repository: any ItineraryRepository
    let cache: any ItineraryCache

    func callAsFunction(_ creation: ItineraryCreation) async throws(ItineraryError) -> ItineraryDetail {
        let detail = try await repository.create(creation)
        // The list's thumbnail comes with the next resync; until then, the saved track.
        // A failed local write is not a failed save: the next resync lists it.
        try? await cache.save(detail, mapPolyline: detail.track.mapPolyline())
        return detail
    }
}
