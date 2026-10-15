import Foundation
import Testing
@testable import StravaClone

/// What another device did, reflected here through simulated realtime events (ADR-030 §9).
@MainActor
struct ItineraryRealtimeSyncTests {
    private struct Context {
        let synchronizer: ItinerarySynchronizer
        let repository: FakeItineraryRepository
        let cache: GRDBItineraryCache
        let queue: GRDBItineraryChangeQueue
        let events: FakeItineraryEventSource
    }

    private func make() throws -> Context {
        let repository = FakeItineraryRepository()
        let database = try AppDatabase.inMemory()
        let cache = GRDBItineraryCache(database: database)
        let queue = GRDBItineraryChangeQueue(database: database)
        let events = FakeItineraryEventSource()
        let changes = ItineraryChangeSender(
            repository: repository,
            cache: cache,
            queue: queue,
            sessionRefresher: FakeSessionRefresher(),
            // The retry after the backoff never fires on its own: only the test's triggers send.
            sleep: ManualSleeper().sleep
        )
        let synchronizer = ItinerarySynchronizer(repository: repository, cache: cache, changes: changes, events: events)
        return Context(synchronizer: synchronizer, repository: repository, cache: cache, queue: queue, events: events)
    }

    /// Sends `events` then ends the stream, and waits until all of them were applied.
    private func deliver(_ events: [ItineraryEvent], in context: Context) async {
        let applying = Task { await context.synchronizer.applyRemoteChanges() }
        events.forEach(context.events.send)
        context.events.finish()
        await applying.value
    }

    @Test func theEchoOfItsOwnWriteIsIgnored() async throws {
        let context = try make()
        try await context.cache.save(.fixture(1, updatedMinutes: 5), mapPolyline: EncodedPolyline(value: "local"))

        await deliver([
            .saved(id: .fixture(1), updatedAt: .fixture(minutes: 5)),
            .saved(id: .fixture(1), updatedAt: .fixture(minutes: 2)),
        ], in: context)

        #expect(context.repository.detailCalls.isEmpty)
    }

    @Test func aNewerSaveReloadsTheDetail() async throws {
        let context = try make()
        try await context.cache.save(.fixture(1, name: "Avant"), mapPolyline: EncodedPolyline(value: "local"))
        context.repository.setDetail(.success(.fixture(1, name: "Après", updatedMinutes: 5)), for: .fixture(1))

        await deliver([.saved(id: .fixture(1), updatedAt: .fixture(minutes: 5))], in: context)

        #expect(context.repository.detailCalls == [.fixture(1)])
        let detail = try #require(try await context.cache.detail(id: .fixture(1)))
        #expect(detail.name == "Après")
        #expect(detail.updatedAt == .fixture(minutes: 5))
        // The list thumbnail stays the server's until the next resync.
        #expect(try await context.cache.summaries(limit: 20).map(\.mapPolyline.value) == ["local"])
    }

    @Test func anItineraryCreatedElsewhereIsListedWithItsDetail() async throws {
        let context = try make()
        let created = ItineraryDetail.fixture(2, name: "Créé ailleurs", updatedMinutes: 5)
        context.repository.setDetail(.success(created), for: .fixture(2))

        await deliver([.saved(id: .fixture(2), updatedAt: .fixture(minutes: 5))], in: context)

        let summaries = try await context.cache.summaries(limit: 20)
        #expect(summaries.map(\.name) == ["Créé ailleurs"])
        #expect(summaries.map(\.mapPolyline) == [created.track.mapPolyline()])
        #expect(try await context.cache.detail(id: .fixture(2)) == created)
    }

    @Test func aFailedReloadLeavesTheCacheAsItWas() async throws {
        let context = try make()
        try await context.cache.save(.fixture(1, name: "Avant"), mapPolyline: EncodedPolyline(value: "local"))
        context.repository.setDetail(.failure(.offline), for: .fixture(1))

        await deliver([.saved(id: .fixture(1), updatedAt: .fixture(minutes: 5))], in: context)

        #expect(try await context.cache.detail(id: .fixture(1))?.name == "Avant")
    }

    @Test func aDeleteRemovesTheItineraryAndItsPendingChanges() async throws {
        let context = try make()
        try await context.cache.save(.fixture(1), mapPolyline: EncodedPolyline(value: "local"))
        try await context.cache.save(.fixture(2), mapPolyline: EncodedPolyline(value: "local"))
        try await context.synchronizer.rename(id: .fixture(1), to: "Renommé hors ligne")

        await deliver([.deleted(id: .fixture(1))], in: context)

        #expect(try await context.cache.summaries(limit: 20).map(\.id) == [.fixture(2)])
        #expect(try await context.cache.detail(id: .fixture(1)) == nil)
        #expect(try await context.queue.pending().isEmpty)
    }

    @Test func theOpenDetailClosesWhenDeletedOnAnotherDevice() async throws {
        let context = try make()
        try await context.cache.save(.fixture(1), mapPolyline: EncodedPolyline(value: "local"))
        let store = ItineraryDetailStore(id: .fixture(1), cache: context.cache, synchronizer: context.synchronizer)
        let observing = Task { await store.observe() }
        await waitUntil { store.summary != nil }

        await deliver([.deleted(id: .fixture(1))], in: context)
        await waitUntil { store.isGone }
        observing.cancel()

        #expect(store.isGone)
    }

    /// Waits for `condition`, failing after about two seconds.
    private func waitUntil(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
        for _ in 0..<400 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Condition never met", sourceLocation: sourceLocation)
    }
}
