import Foundation
import Testing
@testable import StravaClone

/// When the full resync runs (ADR-030 §8) and how it behaves around sign-out.
@MainActor
struct ItinerarySynchronizerTests {
    private func make() throws -> (ItinerarySynchronizer, FakeItineraryRepository, GRDBItineraryCache) {
        let repository = FakeItineraryRepository()
        let cache = GRDBItineraryCache(database: try AppDatabase.inMemory())
        return (ItinerarySynchronizer(repository: repository, cache: cache), repository, cache)
    }

    private func waitForPageCalls(_ count: Int, on repository: FakeItineraryRepository) async {
        while repository.pageCalls.count < count {
            await Task.yield()
        }
    }

    @Test func triggersArrivingDuringAResyncJoinIt() async throws {
        let (synchronizer, repository, cache) = try make()
        repository.setPage(.success(ItineraryPage(items: [.fixture(1)], nextCursor: nil)))
        repository.hold()

        async let first: Void = synchronizer.refresh()
        async let second: Void = synchronizer.refresh()
        await waitForPageCalls(1, on: repository)
        repository.release()
        try await first
        try await second

        #expect(repository.pageCalls == [nil])
        #expect(try await cache.summaries(limit: 20).map(\.id) == [.fixture(1)])
    }

    @Test func signingOutClearsTheCacheAndDropsTheResyncInFlight() async throws {
        let (synchronizer, repository, cache) = try make()
        try await cache.replaceSummaries(with: [.fixture(1)])
        repository.setPage(.success(ItineraryPage(items: [.fixture(2)], nextCursor: nil)))
        repository.hold()
        let resync = Task { try await synchronizer.refresh() }
        await waitForPageCalls(1, on: repository)

        let signOut = Task { await synchronizer.signOut() }
        repository.release()
        await signOut.value
        _ = await resync.result

        #expect(try await cache.summaries(limit: 20).isEmpty)
    }

    @Test func theNetworkComingBackStartsAResync() async throws {
        let (synchronizer, repository, cache) = try make()
        repository.setPage(.success(ItineraryPage(items: [.fixture(1)], nextCursor: nil)))
        let (connectivity, network) = AsyncStream<Bool>.makeStream()
        let observing = Task { await synchronizer.resyncOnReconnection(connectivity) }

        network.yield(true)
        network.yield(false)
        network.yield(true)
        network.finish()
        await observing.value

        #expect(repository.pageCalls == [nil])
        #expect(try await cache.summaries(limit: 20).map(\.id) == [.fixture(1)])
    }
}
