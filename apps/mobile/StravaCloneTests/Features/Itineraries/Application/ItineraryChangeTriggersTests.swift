import Foundation
import Testing
@testable import StravaClone

/// When the pending changes are sent (ADR-030 §8): right after the action, then on every
/// resync trigger (foreground, network back); and what sign-out does with them.
@MainActor
struct ItineraryChangeTriggersTests {
    private struct Harness {
        let synchronizer: ItinerarySynchronizer
        let repository: FakeItineraryRepository
        let cache: GRDBItineraryCache
    }

    private func make() throws -> Harness {
        let repository = FakeItineraryRepository()
        let database = try AppDatabase.inMemory()
        let cache = GRDBItineraryCache(database: database)
        let changes = ItineraryChangeSender(
            repository: repository,
            cache: cache,
            queue: GRDBItineraryChangeQueue(database: database),
            sessionRefresher: FakeSessionRefresher()
        )
        return Harness(
            synchronizer: ItinerarySynchronizer(repository: repository, cache: cache, changes: changes),
            repository: repository,
            cache: cache
        )
    }

    @Test func aResyncFirstSendsWhatWasChangedOffline() async throws {
        let harness = try make()
        try await harness.cache.save(.fixture(1, name: "Nom serveur"), mapPolyline: EncodedPolyline(value: "local"))
        try await harness.synchronizer.rename(id: .fixture(1), to: "Renommé hors ligne")
        #expect(try await harness.cache.summaries(limit: 20).map(\.name) == ["Renommé hors ligne"])

        harness.repository.setChangeResult(.success(()))
        harness.repository.setDetail(.success(.fixture(1, name: "Nom serveur")), for: .fixture(1))
        harness.repository.setPage(.success(ItineraryPage(items: [.fixture(1, name: "Renommé hors ligne")], nextCursor: nil)))
        try await harness.synchronizer.refresh()

        #expect(harness.repository.renameCalls.map(\.1) == ["Renommé hors ligne", "Renommé hors ligne"])
        #expect(await harness.synchronizer.pendingChangeCount() == 0)
        #expect(try await harness.cache.summaries(limit: 20).map(\.name) == ["Renommé hors ligne"])
    }

    @Test func theNetworkComingBackSendsAnOfflineDelete() async throws {
        let harness = try make()
        try await harness.cache.replaceSummaries(with: [.fixture(1)])
        await harness.synchronizer.delete(id: .fixture(1))
        #expect(try await harness.cache.summaries(limit: 20).isEmpty)

        harness.repository.setChangeResult(.success(()))
        let (connectivity, network) = AsyncStream<Bool>.makeStream()
        let observing = Task { await harness.synchronizer.resyncOnReconnection(connectivity) }
        network.yield(false)
        network.yield(true)
        network.finish()
        await observing.value

        #expect(harness.repository.deleteCalls == [.fixture(1), .fixture(1)])
        #expect(await harness.synchronizer.pendingChangeCount() == 0)
        #expect(try await harness.cache.summaries(limit: 20).isEmpty)
    }

    @Test func signingOutWithPendingChangesWarnsThenEmptiesTheQueue() async throws {
        let harness = try make()
        try await harness.cache.replaceSummaries(with: [.fixture(1), .fixture(2)])
        try await harness.synchronizer.rename(id: .fixture(1), to: "Renommé")
        await harness.synchronizer.delete(id: .fixture(2))

        let pending = await harness.synchronizer.pendingChangeCount()
        #expect(pending == 2)
        #expect(ItineraryMessages.signOutWarning(pendingChanges: pending)?.contains("2 modifications") == true)

        await harness.synchronizer.signOut()

        #expect(await harness.synchronizer.pendingChangeCount() == 0)
        #expect(ItineraryMessages.signOutWarning(pendingChanges: 0) == nil)
        #expect(try await harness.cache.summaries(limit: 20).isEmpty)
    }
}
