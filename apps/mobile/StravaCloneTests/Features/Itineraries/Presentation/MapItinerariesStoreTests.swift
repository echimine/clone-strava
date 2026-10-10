import Foundation
import Testing
@testable import StravaClone

/// Map tab carousel (spec #22, ADR-030 §8): the Itineraries from the cache, a resync when it
/// shows, and the card scrolled to framed on the map.
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
            makeDetailStore: { ItineraryDetailStore(id: $0, cache: cache, synchronizer: synchronizer) },
            makeEditFlow: { id in
                ItineraryEditFlow(
                    id: id,
                    isOnline: { true },
                    load: LoadSavedItinerary(repository: repository, cache: cache),
                    makeEditorStore: { ItineraryEditorStore(editor: ItineraryEditor(restoring: $0, router: FakeItineraryRouter())) },
                    makeSaveStore: { ItinerarySaveStore(update: UpdateItinerary(repository: repository, cache: cache), itinerary: $0) },
                    analytics: FakeAnalyticsClient()
                )
            }
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

    @Test func showingTheCarouselResyncsTheList() async throws {
        let context = try make()
        try await context.cache.replaceSummaries(with: [.fixture(1)])
        context.repository.setPage(.success(ItineraryPage(items: [.fixture(2)], nextCursor: nil)))
        let observing = Task { await context.store.list.observe() }
        defer { observing.cancel() }

        await context.store.appeared()
        await waitUntil { context.store.list.itineraries.map(\.id) == [.fixture(2)] }

        #expect(context.repository.pageCalls == [nil])
    }

    /// The tab opens on the athlete: nothing is framed until the carousel is scrolled.
    @Test func nothingIsFramedBeforeTheCarouselIsScrolled() async throws {
        let context = try make()
        try await context.cache.replaceSummaries(with: [.fixture(1), .fixture(2)])
        let observing = Task { await context.store.list.observe() }
        defer { observing.cancel() }
        await waitUntil { context.store.list.hasLoaded }

        #expect(context.store.focusedID == nil)
        #expect(context.store.focusedPath == nil)
    }

    /// Offline too: the map frames the centred card's cached simplified path.
    @Test func scrollingToACardFramesItsPath() async throws {
        let context = try make()
        try await context.cache.replaceSummaries(with: [.fixture(1), .fixture(2, mapPolyline: "_p~iF~ps|U")])
        let observing = Task { await context.store.list.observe() }
        defer { observing.cancel() }
        await waitUntil { context.store.list.hasLoaded }

        context.store.focusedID = .fixture(2)

        // "_p~iF~ps|U" is the start of the reference polyline5 example.
        #expect(context.store.focusedPath == [Coordinate(latitude: 38.5, longitude: -120.2)])
    }

    /// Deleted elsewhere (or `404`): the map frames nothing.
    @Test func anItineraryGoneFromTheCacheIsNoLongerFramed() async throws {
        let context = try make()
        try await context.cache.replaceSummaries(with: [.fixture(1), .fixture(2)])
        let observing = Task { await context.store.list.observe() }
        defer { observing.cancel() }
        await waitUntil { context.store.list.hasLoaded }
        context.store.focusedID = .fixture(1)

        try await context.cache.delete(id: .fixture(1))
        await waitUntil { context.store.list.itineraries.map(\.id) == [.fixture(2)] }

        #expect(context.store.focusedPath == nil)
    }
}
