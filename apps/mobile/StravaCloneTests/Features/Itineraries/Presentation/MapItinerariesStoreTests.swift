import Foundation
import Testing
@testable import StravaClone

/// Map tab sheet (spec #22, ADR-030 §8): the Itineraries from the cache, a resync on
/// opening, and a touch that frames the map on the Itinerary and shows its detail.
@MainActor
struct MapItinerariesStoreTests {
    private struct Context {
        let store: MapItinerariesStore
        let repository: FakeItineraryRepository
        let cache: GRDBItineraryCache
    }

    private func make() throws -> Context {
        let repository = FakeItineraryRepository()
        let cache = GRDBItineraryCache(database: try AppDatabase.inMemory())
        let synchronizer = ItinerarySynchronizer(repository: repository, cache: cache)
        let store = MapItinerariesStore(
            list: ItineraryListStore(cache: cache, synchronizer: synchronizer),
            makeDetailStore: { ItineraryDetailStore(id: $0, cache: cache, synchronizer: synchronizer) }
        )
        return Context(store: store, repository: repository, cache: cache)
    }

    /// Waits for `condition`, failing after about two seconds.
    private func waitUntil(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
        for _ in 0..<400 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Condition never met", sourceLocation: sourceLocation)
    }

    @Test func openingTheSheetResyncsTheList() async throws {
        let context = try make()
        try await context.cache.replaceSummaries(with: [.fixture(1)])
        context.repository.setPage(.success(ItineraryPage(items: [.fixture(2)], nextCursor: nil)))
        let observing = Task { await context.store.list.observe() }
        defer { observing.cancel() }

        await context.store.sheetOpened()
        await waitUntil { context.store.list.itineraries.map(\.id) == [.fixture(2)] }

        #expect(context.repository.pageCalls == [nil])
    }

    /// Offline with no detail prefetched, the map frames the card's simplified path.
    @Test func touchingAnItineraryOfflineFramesTheMapOnItsListedPath() async throws {
        let context = try make()
        try await context.cache.replaceSummaries(with: [.fixture(1, name: "Col du Galibier")])
        context.repository.setDetail(.failure(.offline), for: .fixture(1))

        context.store.select(.fixture(1, name: "Col du Galibier"))
        let detail = try #require(context.store.detail)
        let observing = Task { await detail.observe() }
        defer { observing.cancel() }
        await waitUntil { detail.trackMessage != nil }

        // "_p~iF~ps|U_ulLnnqC" is the reference polyline5 example.
        #expect(context.store.focusedPath == [
            Coordinate(latitude: 38.5, longitude: -120.2),
            Coordinate(latitude: 40.7, longitude: -120.95),
        ])
        #expect(detail.summary?.name == "Col du Galibier")
        #expect(detail.trackMessage == ItineraryMessages.trackUnavailableOffline)
    }

    /// Once the detail is cached, the map frames the full track rather than the thumbnail.
    @Test func aCachedDetailFramesTheMapOnTheFullTrack() async throws {
        let context = try make()
        try await context.cache.save(.fixture(1), mapPolyline: EncodedPolyline(value: "_p~iF~ps|U_ulLnnqC"))

        context.store.select(.fixture(1))
        let detail = try #require(context.store.detail)
        let observing = Task { await detail.observe() }
        defer { observing.cancel() }
        await waitUntil { detail.detail != nil }

        #expect(context.store.focusedPath == [
            Coordinate(latitude: 45.9, longitude: 6.12),
            Coordinate(latitude: 45.91, longitude: 6.12),
            Coordinate(latitude: 45.92, longitude: 6.12),
        ])
    }

    @Test func closingTheDetailGoesBackToTheList() throws {
        let context = try make()
        context.store.select(.fixture(1))

        context.store.closeDetail()

        #expect(context.store.detail == nil)
        #expect(context.store.focusedPath == nil)
    }

    /// Deleted elsewhere (or `404`): the sheet goes back to the list, the map frames nothing.
    @Test func anItineraryGoneFromTheCacheLeavesTheDetail() async throws {
        let context = try make()
        try await context.cache.save(.fixture(1), mapPolyline: EncodedPolyline(value: "_p~iF~ps|U_ulLnnqC"))
        context.store.select(.fixture(1))
        let detail = try #require(context.store.detail)
        let observing = Task { await detail.observe() }
        defer { observing.cancel() }
        await waitUntil { detail.detail != nil }

        try await context.cache.delete(id: .fixture(1))
        await waitUntil { detail.isGone }

        #expect(context.store.detail == nil)
        #expect(context.store.focusedPath == nil)
    }
}
