import Foundation
import Testing
@testable import StravaClone

/// The feed and the Activity detail (ADR-033 §1, §7): only processed cards open the detail,
/// and the cards follow what the detail publishes on the Core change stream.
@MainActor
struct FeedStoreActivityDetailTests {
    private func makeStore(
        _ repository: FakeFeedRepository,
        local: FakeLocalActivityFeedSource = FakeLocalActivityFeedSource(),
        changes: ActivityChanges = ActivityChanges()
    ) -> FeedStore {
        FeedStore(
            loadFeed: LoadFeed(repository: repository),
            toggleKudos: ToggleKudos(repository: repository),
            events: FakeFeedEventSource(),
            localActivities: local,
            activityChanges: changes
        )
    }

    @Test func aProcessedCardOpensTheDetailButALocalCardDoesNot() async {
        let repository = FakeFeedRepository()
        let post = ActivityPost.fixture()
        repository.pages[nil] = .success(FeedPage(posts: [post], nextCursor: nil))
        let local = FakeLocalActivityFeedSource()
        let card = LocalActivityCard.fixture(status: .processing, state: .processing)
        let store = makeStore(repository, local: local)
        local.send([card])
        let observation = Task { await store.observeLocalActivities() }
        while store.localCards.isEmpty { await Task.yield() }
        await store.refresh()

        store.open(card.id)
        #expect(store.path.isEmpty)

        store.open(post.id)
        #expect(store.path == [ActivityDetailRequest(id: post.id)])

        // The comment button opens the same detail, asking for the comments (ADR-034).
        store.path = []
        store.open(post.id, showingComments: true)
        #expect(store.path == [ActivityDetailRequest(id: post.id, showsComments: true)])
        observation.cancel()
    }

    @Test func theCardsFollowWhatTheDetailPublishes() async {
        let repository = FakeFeedRepository()
        let edited = ActivityPost.fixture()
        let deleted = ActivityPost.fixture()
        let commented = ActivityPost.fixture()
        repository.pages[nil] = .success(FeedPage(posts: [edited, deleted, commented], nextCursor: nil))
        let changes = ActivityChanges()
        let store = makeStore(repository, changes: changes)
        await store.refresh()

        let renamed = ActivityPost.fixture(id: edited.id, title: "Sortie vélo", sport: .ride)
        let engagement = ActivityEngagement(kudosCount: 7, commentCount: 3, viewerHasKudoed: true)
        changes.publish(.updated(renamed))
        changes.publish(.deleted(deleted.id))
        changes.publish(.engagement(commented.id, engagement))
        // Unknown to the feed: ignored, never added.
        changes.publish(.updated(.fixture()))

        #expect(await eventually { store.posts.last?.engagement == engagement })
        #expect(store.posts.map(\.id) == [edited.id, commented.id])
        #expect(store.posts.first == renamed)
    }

    /// ADR-033 §1: the long-press menu ("Modifier") is only on my processed cards, never on
    /// another athlete's card or on a local card.
    @Test func onlyMyProcessedCardsHaveTheManageMenu() async {
        let repository = FakeFeedRepository()
        let mine = ActivityPost.fixture(viewerIsAuthor: true)
        let theirs = ActivityPost.fixture(viewerIsAuthor: false)
        repository.pages[nil] = .success(FeedPage(posts: [mine, theirs], nextCursor: nil))
        let local = FakeLocalActivityFeedSource()
        let card = LocalActivityCard.fixture(status: .processing, state: .processing)
        let store = makeStore(repository, local: local)
        local.send([card])
        let observation = Task { await store.observeLocalActivities() }
        while store.localCards.isEmpty { await Task.yield() }
        await store.refresh()

        #expect(store.canManage(mine.id))
        #expect(!store.canManage(theirs.id))
        #expect(!store.canManage(card.id))
        observation.cancel()
    }
}
