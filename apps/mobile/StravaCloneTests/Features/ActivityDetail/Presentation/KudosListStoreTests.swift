import Foundation
import Testing
@testable import StravaClone

/// The sheet listing everyone who gave kudos (ADR-034 §1): most recent first, by pages of 20,
/// the next page loaded near the end of the list.
@MainActor
struct KudosListStoreTests {
    private let activityId = ActivityID()

    private func makeStore(_ repository: FakeActivityKudosRepository) -> KudosListStore {
        KudosListStore(activityId: activityId, loadKudos: LoadKudosList(repository: repository))
    }

    @Test func pagesThroughEveryGiver() async {
        let first = KudosGiver.fixtures(0 ..< 20)
        let second = KudosGiver.fixtures(20 ..< 23)
        let repository = FakeActivityKudosRepository(
            .success(KudosPage(givers: first, nextCursor: "c1")),
            .success(KudosPage(givers: second, nextCursor: nil))
        )
        let store = makeStore(repository)
        #expect(store.phase == .loading)

        await store.load()
        #expect(store.phase == .loaded)
        #expect(store.givers == first)

        // Far from the end: nothing more is fetched.
        await store.loadMoreIfNeeded(current: first[5])
        #expect(repository.pageRequests.count == 1)

        await store.loadMoreIfNeeded(current: first[19])
        #expect(store.givers == first + second)

        // Last page reached.
        await store.loadMoreIfNeeded(current: second[2])
        #expect(repository.pageRequests == [
            .init(activityId: activityId, cursor: nil, limit: 20),
            .init(activityId: activityId, cursor: "c1", limit: 20),
        ])
    }

    @Test func aFailedFirstPageOffersARetry() async {
        let givers = KudosGiver.fixtures(0 ..< 3)
        let repository = FakeActivityKudosRepository(.failure(.offline), .success(KudosPage(givers: givers, nextCursor: nil)))
        let store = makeStore(repository)

        await store.load()
        #expect(store.phase == .failed(message: "Vous êtes hors ligne."))

        await store.load()
        #expect(store.phase == .loaded)
        #expect(store.givers == givers)
    }

    /// A failed next page keeps the givers shown; scrolling to the end tries again.
    @Test func aFailedNextPageKeepsTheListAndRetries() async {
        let first = KudosGiver.fixtures(0 ..< 20)
        let repository = FakeActivityKudosRepository(
            .success(KudosPage(givers: first, nextCursor: "c1")),
            .failure(.network),
            .success(KudosPage(givers: [KudosGiver.fixture(20)], nextCursor: nil))
        )
        let store = makeStore(repository)
        await store.load()

        await store.loadMoreIfNeeded(current: first[19])
        #expect(store.givers == first)
        #expect(store.phase == .loaded)

        await store.loadMoreIfNeeded(current: first[19])
        #expect(store.givers.count == 21)
    }
}
