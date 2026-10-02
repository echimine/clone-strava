import Foundation
import Testing
@testable import StravaClone

@MainActor
struct FeedStoreTests {
    private func makeStore(_ repository: FakeFeedRepository, events: FakeFeedEventSource = FakeFeedEventSource()) -> FeedStore {
        FeedStore(
            loadFeed: LoadFeed(repository: repository),
            toggleKudos: ToggleKudos(repository: repository),
            events: events
        )
    }

    @Test func firstLoadShowsThePosts() async {
        let repository = FakeFeedRepository()
        let post = ActivityPost.fixture()
        repository.pages[nil] = .success(FeedPage(posts: [post], nextCursor: nil))
        let store = makeStore(repository)

        await store.loadIfNeeded()
        await store.loadIfNeeded()

        #expect(store.phase == .loaded)
        #expect(store.posts == [post])
        #expect(repository.requestedCursors == [nil])
    }

    @Test func anEmptyFeedAndAFailureAreDistinct() async {
        let repository = FakeFeedRepository()
        repository.pages[nil] = .success(FeedPage(posts: [], nextCursor: nil))
        let store = makeStore(repository)
        await store.refresh()
        #expect(store.isEmpty)

        let failing = makeStore(FakeFeedRepository())
        await failing.refresh()
        #expect(failing.phase == .failed(message: "Une erreur est survenue, réessayez."))
    }

    @Test func scrollingNearTheEndAppendsTheNextPageWithoutDuplicates() async {
        let repository = FakeFeedRepository()
        let first = (0..<5).map { _ in ActivityPost.fixture() }
        let extra = ActivityPost.fixture()
        repository.pages[nil] = .success(FeedPage(posts: first, nextCursor: "c1"))
        repository.pages["c1"] = .success(FeedPage(posts: [first[4], extra], nextCursor: nil))
        let store = makeStore(repository)
        await store.refresh()

        await store.loadMoreIfNeeded(currentPost: first[0])
        #expect(repository.requestedCursors == [nil])

        await store.loadMoreIfNeeded(currentPost: first[3])
        #expect(store.posts.map(\.id) == first.map(\.id) + [extra.id])

        await store.loadMoreIfNeeded(currentPost: extra)
        #expect(repository.requestedCursors == [nil, "c1"])
    }

    @Test func kudosIsOptimisticThenTakesTheServerCount() async {
        let repository = FakeFeedRepository()
        let post = ActivityPost.fixture(kudos: 2)
        repository.pages[nil] = .success(FeedPage(posts: [post], nextCursor: nil))
        repository.kudosResult = .success(KudosState(kudosCount: 5, viewerHasKudoed: true))
        let (gate, open) = AsyncStream<Void>.makeStream()
        repository.kudosGate = gate
        let store = makeStore(repository)
        await store.refresh()

        let tap = Task { await store.toggleKudos(on: post.id) }
        while repository.kudosCalls.isEmpty { await Task.yield() }
        #expect(store.posts[0].engagement == ActivityEngagement(kudosCount: 3, commentCount: 0, viewerHasKudoed: true))

        // A second tap while the first is in flight is ignored.
        await store.toggleKudos(on: post.id)
        #expect(repository.kudosCalls.count == 1)

        open.yield()
        await tap.value
        #expect(store.posts[0].engagement.kudosCount == 5)
        #expect(repository.kudosCalls.first?.given == true)
    }

    @Test func aFailedKudosRollsBack() async {
        let repository = FakeFeedRepository()
        let post = ActivityPost.fixture(kudos: 2, viewerHasKudoed: true)
        repository.pages[nil] = .success(FeedPage(posts: [post], nextCursor: nil))
        repository.kudosResult = .failure(.offline)
        let store = makeStore(repository)
        await store.refresh()

        await store.toggleKudos(on: post.id)

        #expect(repository.kudosCalls.first?.given == false)
        #expect(store.posts[0].engagement == post.engagement)
        #expect(store.notice == "Kudos non envoyé : vous êtes hors ligne.")
    }

    @Test func noKudosOnOwnActivity() async {
        let repository = FakeFeedRepository()
        let post = ActivityPost.fixture(viewerIsAuthor: true)
        repository.pages[nil] = .success(FeedPage(posts: [post], nextCursor: nil))
        let store = makeStore(repository)
        await store.refresh()

        await store.toggleKudos(on: post.id)

        #expect(repository.kudosCalls.isEmpty)
    }

    @Test func aProcessedActivityReloadsTheFeed() async {
        let repository = FakeFeedRepository()
        let events = FakeFeedEventSource()
        repository.pages[nil] = .success(FeedPage(posts: [], nextCursor: nil))
        let store = makeStore(repository, events: events)
        await store.refresh()

        let fresh = ActivityPost.fixture()
        repository.pages[nil] = .success(FeedPage(posts: [fresh], nextCursor: nil))
        let observing = Task { await store.observeActivityChanges() }
        events.continuation.yield()
        events.continuation.finish()
        await observing.value

        #expect(store.posts == [fresh])
    }

    @Test func resetForgetsThePreviousAccount() async {
        let repository = FakeFeedRepository()
        repository.pages[nil] = .success(FeedPage(posts: [.fixture()], nextCursor: "c1"))
        let store = makeStore(repository)
        await store.refresh()

        store.reset()

        #expect(store.posts.isEmpty)
        #expect(store.phase == .idle)
    }
}
