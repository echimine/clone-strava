import Foundation
import Testing
@testable import StravaClone

/// The `sync_operation` queue and what the cache shows while a change is pending
/// (ADR-008 §3, ADR-030 §8), on an in-memory database with the real migrations.
struct GRDBItineraryChangeQueueTests {
    private func make() throws -> (GRDBItineraryChangeQueue, GRDBItineraryCache) {
        let database = try AppDatabase.inMemory()
        return (GRDBItineraryChangeQueue(database: database), GRDBItineraryCache(database: database))
    }

    // MARK: Coalescing

    @Test func onlyTheLastRenameIsKept() async throws {
        let (queue, _) = try make()

        try await queue.enqueue(.rename(name: "Premier"), for: .fixture(1), at: .fixture())
        try await queue.enqueue(.rename(name: "Second"), for: .fixture(1), at: .fixture(minutes: 1))
        try await queue.enqueue(.rename(name: "Autre"), for: .fixture(2), at: .fixture(minutes: 2))

        let pending = try await queue.pending()
        #expect(pending.map(\.itineraryID) == [.fixture(1), .fixture(2)])
        #expect(pending.map(\.change) == [.rename(name: "Second"), .rename(name: "Autre")])
        #expect(pending.first?.attempts == 0)
        #expect(pending.first?.nextAttemptAt == .fixture(minutes: 1))
    }

    @Test func aDeleteCancelsAPendingRename() async throws {
        let (queue, _) = try make()

        try await queue.enqueue(.rename(name: "Premier"), for: .fixture(1), at: .fixture())
        try await queue.enqueue(.delete, for: .fixture(1), at: .fixture())
        try await queue.enqueue(.delete, for: .fixture(1), at: .fixture())
        try await queue.enqueue(.rename(name: "Trop tard"), for: .fixture(1), at: .fixture())

        #expect(try await queue.pending().map(\.change) == [.delete])
    }

    @Test func aFailedSendIsPostponedAndCounted() async throws {
        let (queue, _) = try make()
        try await queue.enqueue(.delete, for: .fixture(1), at: .fixture())
        let change = try #require(try await queue.pending().first)

        try await queue.postpone(change, until: .fixture(minutes: 5), error: "offline")

        let postponed = try #require(try await queue.pending().first)
        #expect(postponed.attempts == 1)
        #expect(postponed.nextAttemptAt == .fixture(minutes: 5))
    }

    @Test func removingASentRenameKeepsANewerOne() async throws {
        let (queue, _) = try make()
        try await queue.enqueue(.rename(name: "Envoyé"), for: .fixture(1), at: .fixture())
        let sent = try #require(try await queue.pending().first)
        try await queue.enqueue(.rename(name: "Plus récent"), for: .fixture(1), at: .fixture())

        try await queue.remove(sent)

        #expect(try await queue.pending().map(\.change) == [.rename(name: "Plus récent")])
    }

    // MARK: The local value wins while pending

    @Test func aPendingRenameWinsOverTheServerName() async throws {
        let (queue, cache) = try make()
        try await cache.save(.fixture(1, name: "Nom serveur"), mapPolyline: EncodedPolyline(value: "local"))

        try await queue.enqueue(.rename(name: "Nom local"), for: .fixture(1), at: .fixture())
        try await cache.replaceSummaries(with: [.fixture(1, name: "Nom serveur", updatedMinutes: 5)])

        #expect(try await cache.summaries(limit: 20).map(\.name) == ["Nom local"])
        #expect(try await cache.detail(id: .fixture(1))?.name == "Nom local")
        var observed = cache.observeItinerary(id: .fixture(1)).makeAsyncIterator()
        #expect(await observed.next()??.summary.name == "Nom local")
    }

    @Test func anItineraryPendingDeletionStaysHidden() async throws {
        let (queue, cache) = try make()
        try await cache.save(.fixture(1), mapPolyline: EncodedPolyline(value: "local"))
        try await cache.replaceSummaries(with: [.fixture(1), .fixture(2)])

        try await queue.enqueue(.delete, for: .fixture(1), at: .fixture())
        try await cache.replaceSummaries(with: [.fixture(1), .fixture(2)])

        #expect(try await cache.summaries(limit: 20).map(\.id) == [.fixture(2)])
        #expect(try await cache.detail(id: .fixture(1)) == nil)
        #expect(try await cache.idsWithStaleDetail() == [.fixture(2)])
        var observed = cache.observeItinerary(id: .fixture(1)).makeAsyncIterator()
        #expect(await observed.next() == .some(nil))
    }

    @Test func aResyncKeepsTheRowsAPendingChangeTargets() async throws {
        let (queue, cache) = try make()
        try await cache.replaceSummaries(with: [.fixture(1), .fixture(2), .fixture(3)])
        try await queue.enqueue(.rename(name: "Renommé"), for: .fixture(1), at: .fixture())
        try await queue.enqueue(.delete, for: .fixture(2), at: .fixture())

        try await cache.replaceSummaries(with: [])

        #expect(try await cache.summaries(limit: 20).map(\.id) == [.fixture(1)])
        try await queue.remove(try #require(try await queue.pending().last))
        #expect(try await cache.summaries(limit: 20).map(\.id) == [.fixture(1), .fixture(2)])
    }

    @Test func droppingThePendingRenameShowsTheServerNameAgain() async throws {
        let (queue, cache) = try make()
        try await cache.replaceSummaries(with: [.fixture(1, name: "Nom serveur")])
        try await queue.enqueue(.rename(name: "Refusé"), for: .fixture(1), at: .fixture())

        try await queue.remove(try #require(try await queue.pending().first))

        #expect(try await cache.summaries(limit: 20).map(\.name) == ["Nom serveur"])
    }

    /// Deleted elsewhere (`404`, `itinerary.deleted` in #39): its pending changes go with it.
    @Test func forgettingAnItineraryDropsItsPendingChanges() async throws {
        let (queue, cache) = try make()
        try await cache.replaceSummaries(with: [.fixture(1), .fixture(2)])
        try await queue.enqueue(.rename(name: "Renommé"), for: .fixture(1), at: .fixture())
        try await queue.enqueue(.delete, for: .fixture(2), at: .fixture())

        try await cache.delete(id: .fixture(1))

        #expect(try await queue.pending().map(\.itineraryID) == [.fixture(2)])
        #expect(try await cache.summaries(limit: 20).isEmpty)
    }

    @Test func signingOutForgetsEveryPendingChange() async throws {
        let (queue, _) = try make()
        try await queue.enqueue(.rename(name: "Renommé"), for: .fixture(1), at: .fixture())
        try await queue.enqueue(.delete, for: .fixture(2), at: .fixture())

        try await queue.clear()

        #expect(try await queue.pending().isEmpty)
    }
}
