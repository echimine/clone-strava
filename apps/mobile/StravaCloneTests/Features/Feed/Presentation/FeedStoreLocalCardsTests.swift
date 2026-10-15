import Foundation
import Testing
@testable import StravaClone

/// Local Activities on top of the feed (ADR-031 §14): newest first, dropped once the server
/// returns them, Delete and Retry.
@MainActor
struct FeedStoreLocalCardsTests {
    private func makeStore(_ repository: FakeFeedRepository, local: FakeLocalActivityFeedSource) -> FeedStore {
        FeedStore(
            loadFeed: LoadFeed(repository: repository),
            toggleKudos: ToggleKudos(repository: repository),
            events: FakeFeedEventSource(),
            localActivities: local
        )
    }

    /// Runs `observeLocalActivities()` until `condition` holds.
    private func observe(_ store: FeedStore, until condition: () -> Bool) async -> Task<Void, Never> {
        let observation = Task { await store.observeLocalActivities() }
        while !condition() { await Task.yield() }
        return observation
    }

    @Test func localCardsComeOnTopAndThoseTheServerReturnedAreDropped() async {
        let repository = FakeFeedRepository()
        let local = FakeLocalActivityFeedSource()
        let waiting = LocalActivityCard.fixture(status: .waitingForNetwork)
        let processed = LocalActivityCard.fixture(status: .processing, state: .processing)
        repository.pages[nil] = .success(FeedPage(posts: [.fixture(id: processed.id), .fixture()], nextCursor: nil))
        let store = makeStore(repository, local: local)
        local.send([waiting, processed])
        let observation = await observe(store) { !store.localCards.isEmpty }
        #expect(store.localCards == [waiting, processed])

        await store.refresh()

        #expect(store.localCards == [waiting])
        observation.cancel()
    }

    @Test func localCardsShowEvenWhenTheFeedCannotLoad() async {
        let local = FakeLocalActivityFeedSource()
        let card = LocalActivityCard.fixture()
        let store = makeStore(FakeFeedRepository(), local: local)
        local.send([card])
        let observation = await observe(store) { !store.localCards.isEmpty }

        await store.refresh()

        #expect(store.localCards == [card])
        #expect(!store.isEmpty)
        #expect(store.notice == nil)
        observation.cancel()
    }

    @Test func deleteAndRetryReachTheLocalActivities() async {
        let local = FakeLocalActivityFeedSource()
        let card = LocalActivityCard.fixture(status: .failed(reason: "validation_error"), state: .failed)
        let store = makeStore(FakeFeedRepository(), local: local)

        await store.deleteLocalActivity(card.id)
        await store.retryLocalActivity(card.id)

        #expect(local.deleted == [card.id])
        #expect(local.retried == [card.id])
    }

    @Test func aRefusedActionIsReported() async {
        let local = FakeLocalActivityFeedSource()
        local.actionError = LocalActivityActionError.notAllowed
        let store = makeStore(FakeFeedRepository(), local: local)

        await store.deleteLocalActivity(ActivityID())

        #expect(store.notice == FeedMessages.localActionRefused)
    }
}
