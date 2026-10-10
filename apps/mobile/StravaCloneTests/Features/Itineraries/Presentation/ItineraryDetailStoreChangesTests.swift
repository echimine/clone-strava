import Foundation
import Testing
@testable import StravaClone

/// Renommer and Supprimer from the detail page (ADR-030 §8): the effect shows at once, even
/// offline, before the change is sent.
@MainActor
struct ItineraryDetailStoreChangesTests {
    private func make() throws -> (ItineraryDetailStore, GRDBItineraryCache) {
        let repository = FakeItineraryRepository()
        let database = try AppDatabase.inMemory()
        let cache = GRDBItineraryCache(database: database)
        let changes = ItineraryChangeSender(
            repository: repository,
            cache: cache,
            queue: GRDBItineraryChangeQueue(database: database),
            sessionRefresher: FakeSessionRefresher()
        )
        let synchronizer = ItinerarySynchronizer(repository: repository, cache: cache, changes: changes)
        return (ItineraryDetailStore(id: .fixture(1), cache: cache, synchronizer: synchronizer), cache)
    }

    /// Waits for the store to reach `condition`, failing after about two seconds.
    private func waitUntil(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
        for _ in 0..<400 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Condition never met", sourceLocation: sourceLocation)
    }

    @Test func anOfflineRenameShowsAtOnce() async throws {
        let (store, cache) = try make()
        try await cache.save(.fixture(1, name: "Nom serveur"), mapPolyline: EncodedPolyline(value: "local"))
        let observing = Task { await store.observe() }
        await waitUntil { store.summary != nil }

        #expect(await store.rename(to: "Tour du lac"))
        await waitUntil { store.summary?.name == "Tour du lac" }
        observing.cancel()

        #expect(store.detail?.name == "Tour du lac")
        #expect(store.isGone == false)
    }

    @Test func aNameOutOfBoundsIsNotAccepted() async throws {
        let (store, _) = try make()

        #expect(ItineraryDetailStore.isValidName("Tour du lac"))
        #expect(!ItineraryDetailStore.isValidName("  "))
        #expect(await store.rename(to: "  ") == false)
    }

    @Test func anOfflineDeleteClosesThePageAtOnce() async throws {
        let (store, cache) = try make()
        try await cache.save(.fixture(1), mapPolyline: EncodedPolyline(value: "local"))
        let observing = Task { await store.observe() }
        await waitUntil { store.summary != nil }

        await store.delete()

        await waitUntil { store.isGone }
        observing.cancel()
        #expect(try await cache.summaries(limit: 20).isEmpty)
    }
}
