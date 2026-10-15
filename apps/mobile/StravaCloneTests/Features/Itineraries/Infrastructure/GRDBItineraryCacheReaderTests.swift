import Foundation
import Testing
@testable import StravaClone

/// The read side of the Itinerary cache that Recording sees through `Core/Domain`
/// (ADR-031 §15), on an in-memory database with the real migrations.
struct GRDBItineraryCacheReaderTests {
    private func make() throws -> (reader: any ItineraryCacheReader, cache: GRDBItineraryCache, queue: GRDBItineraryChangeQueue) {
        let database = try AppDatabase.inMemory()
        let cache = GRDBItineraryCache(database: database)
        return (cache, cache, GRDBItineraryChangeQueue(database: database))
    }

    @Test func listsEveryCachedItineraryMostRecentFirstWithItsSportAndWhetherItsTrackIsCached() async throws {
        let (reader, cache, _) = try make()
        try await cache.replaceSummaries(with: [
            .fixture(1, name: "Tour du lac", sport: .run, distance: 10_000, updatedMinutes: 10),
            .fixture(2, name: "Col", sport: .ride, distance: 42_500, updatedMinutes: 30),
        ])
        try await cache.store(.fixture(1, name: "Tour du lac", sport: .run, updatedMinutes: 10))

        let listed = try await reader.cachedItineraries()

        #expect(listed == [
            CachedItineraryListing(id: .fixture(2), name: "Col", sport: .ride, distance: Distance(meters: 42_500), hasTrack: false),
            CachedItineraryListing(id: .fixture(1), name: "Tour du lac", sport: .run, distance: Distance(meters: 2_224), hasTrack: true),
        ])
    }

    @Test func loadsTheCachedTrackWithTheTotalDistance() async throws {
        let (reader, cache, _) = try make()
        try await cache.save(.fixture(1), mapPolyline: EncodedPolyline(value: "_p~iF~ps|U"))

        let track = try await reader.track(of: .fixture(1))

        #expect(track == CachedItineraryTrack(
            id: .fixture(1),
            points: [
                Coordinate(latitude: 45.9, longitude: 6.12),
                Coordinate(latitude: 45.91, longitude: 6.12),
                Coordinate(latitude: 45.92, longitude: 6.12),
            ],
            distance: Distance(meters: 2_224)
        ))
    }

    @Test func hasNoTrackForAnItineraryListedWithoutOneOrNotCached() async throws {
        let (reader, cache, _) = try make()
        try await cache.replaceSummaries(with: [.fixture(1)])

        #expect(try await reader.track(of: .fixture(1)) == nil)
        #expect(try await reader.track(of: .fixture(2)) == nil)
    }

    @Test func anItineraryPendingDeletionIsNeitherListedNorLoaded() async throws {
        let (reader, cache, queue) = try make()
        try await cache.save(.fixture(1), mapPolyline: EncodedPolyline(value: "_p~iF~ps|U"))
        try await cache.save(.fixture(2), mapPolyline: EncodedPolyline(value: "_p~iF~ps|U"))
        try await queue.enqueue(.delete, for: .fixture(1), at: .fixture())
        try await queue.enqueue(.rename(name: "Renommé"), for: .fixture(2), at: .fixture())

        #expect(try await reader.cachedItineraries().map(\.name) == ["Renommé"])
        #expect(try await reader.track(of: .fixture(1)) == nil)
    }
}
