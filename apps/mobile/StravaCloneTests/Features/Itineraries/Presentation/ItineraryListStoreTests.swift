import Foundation
import Testing
@testable import StravaClone

/// Profil > Mes Itinéraires (ADR-030 §8): read from the cache, refreshed by a full resync.
@MainActor
struct ItineraryListStoreTests {
    private struct Context {
        let store: ItineraryListStore
        let repository: FakeItineraryRepository
        let cache: GRDBItineraryCache
    }

    private func make(pageSize: Int = 20) throws -> Context {
        let repository = FakeItineraryRepository()
        let cache = GRDBItineraryCache(database: try AppDatabase.inMemory())
        let synchronizer = ItinerarySynchronizer(repository: repository, cache: cache)
        return Context(
            store: ItineraryListStore(cache: cache, synchronizer: synchronizer, pageSize: pageSize),
            repository: repository,
            cache: cache
        )
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0 ..< 10_000 where !condition() {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    @Test func offlineTheListIsShownFromTheCache() async throws {
        let context = try make()
        try await context.cache.replaceSummaries(with: [.fixture(1, updatedMinutes: 5), .fixture(2)])
        context.repository.setPage(.failure(.offline))
        let observing = Task { await context.store.observe() }
        defer { observing.cancel() }

        await context.store.refresh()
        await waitUntil { context.store.itineraries.count == 2 }

        #expect(context.store.itineraries.map(\.id) == [.fixture(1), .fixture(2)])
        #expect(context.store.syncMessage == "Hors ligne : Itinéraires enregistrés sur l'appareil.")
        #expect(!context.store.isEmpty)
    }

    @Test func aSavedItineraryAppearsAtOnce() async throws {
        let context = try make()
        let observing = Task { await context.store.observe() }
        defer { observing.cancel() }
        await waitUntil { context.store.isEmpty }
        context.repository.createResults = [.success(.fixture(3, name: "Tour du lac"))]

        _ = try await SaveItinerary(repository: context.repository, cache: context.cache)(ItineraryCreation(
            id: .fixture(3), name: "Tour du lac", sport: .hike, waypoints: [], legs: []
        ))
        await waitUntil { !context.store.itineraries.isEmpty }

        #expect(context.store.itineraries.map(\.name) == ["Tour du lac"])
    }

    @Test func cardsAreLoadedPageByPage() async throws {
        let context = try make(pageSize: 2)
        try await context.cache.replaceSummaries(with: (1 ... 3).map { .fixture($0, updatedMinutes: Double(-$0)) })
        var observing = Task { await context.store.observe() }
        await waitUntil { context.store.itineraries.count == 2 }
        #expect(context.store.itineraries.map(\.id) == [.fixture(1), .fixture(2)])

        context.store.loadMoreIfNeeded(current: context.store.itineraries[0])
        #expect(context.store.limit == 2)
        context.store.loadMoreIfNeeded(current: context.store.itineraries[1])
        #expect(context.store.limit == 4)

        // The view restarts the observation when the limit changes (`.task(id:)`).
        observing.cancel()
        observing = Task { await context.store.observe() }
        defer { observing.cancel() }
        await waitUntil { context.store.itineraries.count == 3 }
        #expect(context.store.itineraries.map(\.id) == [.fixture(1), .fixture(2), .fixture(3)])
    }

    @Test func refreshingReplacesTheListWithTheServers() async throws {
        let context = try make()
        try await context.cache.replaceSummaries(with: [.fixture(1)])
        context.repository.setPage(.success(ItineraryPage(items: [.fixture(2)], nextCursor: nil)))
        let observing = Task { await context.store.observe() }
        defer { observing.cancel() }

        await context.store.refresh()
        await waitUntil { context.store.itineraries.map(\.id) == [.fixture(2)] }

        #expect(context.store.itineraries.map(\.id) == [.fixture(2)])
        #expect(context.store.syncMessage == nil)
    }
}

@MainActor
struct ItineraryCreationFlowTests {
    @Test func creatingOpensTheEditorWhenOnline() {
        let flow = ItineraryCreationFlow(isOnline: { true })

        flow.start()

        #expect(flow.isPresented)
        #expect(flow.toast == nil)
    }

    /// "Créer" stays active offline and says why nothing opens (ADR-030 §8).
    @Test func creatingOfflineShowsConnectionRequired() {
        let flow = ItineraryCreationFlow(isOnline: { false })

        flow.start()

        #expect(!flow.isPresented)
        #expect(flow.toast == "Connexion requise")
    }
}
