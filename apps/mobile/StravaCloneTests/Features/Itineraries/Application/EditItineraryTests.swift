import Foundation
import Testing
@testable import StravaClone

/// "Modifier" (ADR-030 §5, §8): the Waypoints and Legs are loaded online, and the edit is
/// saved on the same Itinerary, its detail written straight to the cache.
struct EditItineraryTests {
    private let saved = SavedItinerary(
        id: .fixture(1),
        name: "Tour du lac",
        sport: .hike,
        waypoints: [Coordinate(latitude: 45.9, longitude: 6.12), Coordinate(latitude: 45.92, longitude: 6.12)],
        legs: [.straight]
    )

    @Test func loadingReturnsTheStoredWaypointsAndLegs() async throws {
        let repository = FakeItineraryRepository()
        repository.setSavedItinerary(.success(saved), for: .fixture(1))
        let cache = GRDBItineraryCache(database: try AppDatabase.inMemory())

        let loaded = try await LoadSavedItinerary(repository: repository, cache: cache)(id: .fixture(1))

        #expect(loaded == saved)
    }

    /// Deleted elsewhere: it leaves the cache, so its detail closes (ADR-030 §8).
    @Test func anItineraryGoneFromTheServerIsForgotten() async throws {
        let repository = FakeItineraryRepository()
        repository.setSavedItinerary(.failure(.notFound), for: .fixture(1))
        let cache = GRDBItineraryCache(database: try AppDatabase.inMemory())
        try await cache.save(.fixture(1), mapPolyline: EncodedPolyline(value: "_p~iF~ps|U"))

        await #expect(throws: ItineraryError.notFound) {
            try await LoadSavedItinerary(repository: repository, cache: cache)(id: .fixture(1))
        }
        #expect(try await cache.summaries(limit: 20).isEmpty)
    }

    @Test func aSavedEditUpdatesTheSameItineraryInTheList() async throws {
        let repository = FakeItineraryRepository()
        let cache = GRDBItineraryCache(database: try AppDatabase.inMemory())
        try await cache.save(.fixture(1, name: "Tour du lac"), mapPolyline: EncodedPolyline(value: "_p~iF~ps|U"))
        try await cache.save(.fixture(2, updatedMinutes: 5), mapPolyline: EncodedPolyline(value: "_p~iF~ps|U"))
        let edited = ItineraryDetail.fixture(1, name: "Tour du lac", updatedMinutes: 10)
        repository.updateResults = [.success(edited)]
        let edit = ItineraryCreation(id: .fixture(1), name: "Tour du lac", sport: .hike, waypoints: saved.geometry.waypoints, legs: [.straight])

        let detail = try await UpdateItinerary(repository: repository, cache: cache)(edit)

        #expect(detail == edited)
        #expect(repository.updates == [edit])
        #expect(repository.creations.isEmpty)
        let summaries = try await cache.summaries(limit: 20)
        #expect(summaries.map(\.id) == [.fixture(1), .fixture(2)])
        #expect(summaries.first?.updatedAt == .fixture(minutes: 10))
        #expect(try await cache.detail(id: .fixture(1)) == edited)
    }

    @Test func aFailedEditLeavesTheCacheUntouched() async throws {
        let repository = FakeItineraryRepository()
        let cache = GRDBItineraryCache(database: try AppDatabase.inMemory())
        let before = ItineraryDetail.fixture(1)
        try await cache.save(before, mapPolyline: EncodedPolyline(value: "_p~iF~ps|U"))
        repository.updateResults = [.failure(.unavailable)]
        let edit = ItineraryCreation(id: .fixture(1), name: "Tour", sport: .hike, waypoints: saved.geometry.waypoints, legs: [.straight])

        await #expect(throws: ItineraryError.unavailable) {
            try await UpdateItinerary(repository: repository, cache: cache)(edit)
        }
        #expect(try await cache.detail(id: .fixture(1)) == before)
    }
}
