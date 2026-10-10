import Foundation
import Testing
@testable import StravaClone

/// Each detail is prefetched when its Itinerary's `updatedAt` changes, so that any detail
/// opens offline; a `404` deletes the Itinerary locally (ADR-030 §8).
@MainActor
struct ItineraryDetailPrefetchTests {
    private func make() throws -> (ItinerarySynchronizer, FakeItineraryRepository, GRDBItineraryCache) {
        let repository = FakeItineraryRepository()
        let cache = GRDBItineraryCache(database: try AppDatabase.inMemory())
        return (ItinerarySynchronizer(repository: repository, cache: cache), repository, cache)
    }

    @Test func aResyncFetchesTheDetailOfAnItineraryUpdatedElsewhere() async throws {
        let (synchronizer, repository, cache) = try make()
        try await cache.save(.fixture(1), mapPolyline: EncodedPolyline(value: "local"))
        repository.setPage(.success(ItineraryPage(items: [.fixture(1, name: "Modifié", updatedMinutes: 5)], nextCursor: nil)))
        let updated = ItineraryDetail.fixture(1, name: "Modifié", elevationSource: .mixed, updatedMinutes: 5)
        repository.setDetail(.success(updated), for: .fixture(1))

        try await synchronizer.refresh()

        #expect(repository.detailCalls == [.fixture(1)])
        #expect(try await cache.detail(id: .fixture(1)) == updated)
    }

    @Test func aResyncFetchesTheDetailOfANewItinerary() async throws {
        let (synchronizer, repository, cache) = try make()
        repository.setPage(.success(ItineraryPage(items: [.fixture(2)], nextCursor: nil)))
        repository.setDetail(.success(.fixture(2)), for: .fixture(2))

        try await synchronizer.refresh()

        #expect(repository.detailCalls == [.fixture(2)])
        #expect(try await cache.detail(id: .fixture(2)) == .fixture(2))
    }

    @Test func anUnchangedDetailIsNotFetchedAgain() async throws {
        let (synchronizer, repository, cache) = try make()
        try await cache.save(.fixture(1), mapPolyline: EncodedPolyline(value: "local"))
        repository.setPage(.success(ItineraryPage(items: [.fixture(1)], nextCursor: nil)))

        try await synchronizer.refresh()

        #expect(repository.detailCalls.isEmpty)
        #expect(try await cache.detail(id: .fixture(1))?.updatedAt == .fixture())
    }

    @Test func aNotFoundDetailDeletesTheItineraryFromTheCache() async throws {
        let (synchronizer, repository, cache) = try make()
        repository.setPage(.success(ItineraryPage(items: [.fixture(1), .fixture(2)], nextCursor: nil)))
        repository.setDetail(.failure(.notFound), for: .fixture(1))
        repository.setDetail(.success(.fixture(2)), for: .fixture(2))

        try await synchronizer.refresh()

        #expect(try await cache.summaries(limit: 20).map(\.id) == [.fixture(2)])
        #expect(try await cache.detail(id: .fixture(1)) == nil)
    }

    @Test func aDetailThatCouldNotBeFetchedIsTriedAgainOnTheNextResync() async throws {
        let (synchronizer, repository, cache) = try make()
        try await cache.save(.fixture(1), mapPolyline: EncodedPolyline(value: "local"))
        repository.setPage(.success(ItineraryPage(items: [.fixture(1, updatedMinutes: 5)], nextCursor: nil)))
        repository.setDetail(.failure(.network), for: .fixture(1))

        try await synchronizer.refresh()
        #expect(try await cache.detail(id: .fixture(1))?.updatedAt == .fixture())

        repository.setDetail(.success(.fixture(1, updatedMinutes: 5)), for: .fixture(1))
        try await synchronizer.refresh()

        #expect(repository.detailCalls == [.fixture(1), .fixture(1)])
        #expect(try await cache.detail(id: .fixture(1))?.updatedAt == .fixture(minutes: 5))
    }

    @Test func loadingOneDetailThatIsNotFoundDeletesItLocally() async throws {
        let (synchronizer, repository, cache) = try make()
        try await cache.save(.fixture(1), mapPolyline: EncodedPolyline(value: "local"))
        repository.setDetail(.failure(.notFound), for: .fixture(1))

        await #expect(throws: ItineraryError.notFound) { try await synchronizer.loadDetail(id: .fixture(1)) }

        #expect(try await cache.summaries(limit: 20).isEmpty)
    }
}
