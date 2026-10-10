import Foundation
import Testing
@testable import StravaClone

/// The Itinerary cache on an in-memory database with the real migrations (ADR-025, ADR-030 §8).
struct GRDBItineraryCacheTests {
    private func makeCache() throws -> GRDBItineraryCache {
        GRDBItineraryCache(database: try AppDatabase.inMemory())
    }

    @Test func aSavedItineraryIsListedAndItsDetailKept() async throws {
        let cache = try makeCache()
        let detail = ItineraryDetail.fixture(1, name: "Tour du lac", sport: .hike, elevationSource: .mixed)

        try await cache.save(detail, mapPolyline: EncodedPolyline(value: "_p~iF~ps|U"))

        let summaries = try await cache.summaries(limit: 20)
        #expect(summaries == [
            ItinerarySummary(
                id: .fixture(1),
                name: "Tour du lac",
                sport: .hike,
                distance: Distance(meters: 2_224),
                elevationGain: 87.5,
                mapPolyline: EncodedPolyline(value: "_p~iF~ps|U"),
                updatedAt: .fixture()
            ),
        ])
        let saved = try await cache.detail(id: .fixture(1))
        #expect(saved == detail)
    }

    @Test func theListIsSortedByMostRecentlyUpdatedAndReadPageByPage() async throws {
        let cache = try makeCache()
        try await cache.replaceSummaries(with: [
            .fixture(1, updatedMinutes: 10),
            .fixture(2, updatedMinutes: 30),
            .fixture(3, updatedMinutes: 20),
        ])

        #expect(try await cache.summaries(limit: 20).map(\.id) == [.fixture(2), .fixture(3), .fixture(1)])
        #expect(try await cache.summaries(limit: 2).map(\.id) == [.fixture(2), .fixture(3)])
    }

    @Test func replacingTheListUpdatesRowsAndDeletesTheOnesNoLongerReturned() async throws {
        let cache = try makeCache()
        try await cache.save(.fixture(1), mapPolyline: EncodedPolyline(value: "local"))
        try await cache.save(.fixture(2), mapPolyline: EncodedPolyline(value: "local"))

        try await cache.replaceSummaries(with: [
            .fixture(1, name: "Renommé ailleurs", mapPolyline: "server", updatedMinutes: 5),
            .fixture(3),
        ])

        let summaries = try await cache.summaries(limit: 20)
        #expect(summaries.map(\.id) == [.fixture(1), .fixture(3)])
        #expect(summaries.first?.name == "Renommé ailleurs")
        #expect(summaries.first?.mapPolyline == EncodedPolyline(value: "server"))
        #expect(try await cache.detail(id: .fixture(1)) != nil)
        #expect(try await cache.detail(id: .fixture(2)) == nil)
    }

    @Test func theListIsObservedLive() async throws {
        let cache = try makeCache()
        var updates = cache.observeSummaries(limit: 20).makeAsyncIterator()
        #expect(await updates.next() == [])

        try await cache.save(.fixture(1), mapPolyline: EncodedPolyline(value: "_p~iF~ps|U"))

        #expect(await updates.next()?.map(\.id) == [.fixture(1)])
    }

    @Test func clearingEmptiesTheItineraryTables() async throws {
        let cache = try makeCache()
        try await cache.save(.fixture(1), mapPolyline: EncodedPolyline(value: "_p~iF~ps|U"))
        try await cache.replaceSummaries(with: [.fixture(1), .fixture(2)])

        try await cache.clear()

        #expect(try await cache.summaries(limit: 20).isEmpty)
        #expect(try await cache.detail(id: .fixture(1)) == nil)
    }
}
