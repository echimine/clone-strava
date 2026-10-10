import Foundation

/// "Modifier" loads a saved Itinerary's Waypoints and Legs online (ADR-030 §8: they are not
/// cached). A `404` means it is gone: it leaves the cache, and its detail closes.
struct LoadSavedItinerary: Sendable {
    let repository: any ItineraryRepository
    let cache: any ItineraryCache

    func callAsFunction(id: ItineraryID) async throws(ItineraryError) -> SavedItinerary {
        do {
            return try await repository.savedItinerary(id: id)
        } catch {
            if error == .notFound {
                try? await cache.delete(id: id)
            }
            throw error
        }
    }
}

/// Saves an edited Itinerary (ADR-030 §6, §8): `PUT` on the same id, never a copy, then the
/// detail is written straight to the cache, so the detail and the list show the edit at
/// once. On failure nothing is written and the editor keeps its draft.
struct UpdateItinerary: Sendable {
    let repository: any ItineraryRepository
    let cache: any ItineraryCache

    func callAsFunction(_ edit: ItineraryCreation) async throws(ItineraryError) -> ItineraryDetail {
        let detail = try await repository.update(edit)
        // A failed local write is not a failed save: the next resync brings it.
        try? await cache.save(detail, mapPolyline: detail.track.mapPolyline())
        return detail
    }
}
