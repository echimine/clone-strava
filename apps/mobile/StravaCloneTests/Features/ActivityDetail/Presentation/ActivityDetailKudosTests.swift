import Foundation
import Testing
@testable import StravaClone

/// The kudos block of the Activity detail (ADR-034 §1): count, kudos button hidden on the
/// viewer's own Activity, a row of at most 5 recent givers, and an optimistic toggle whose
/// counts reach the feed through the Core change stream (ADR-033 §7).
@MainActor
struct ActivityDetailKudosTests {
    private func makeStore(
        _ detail: ActivityDetail,
        kudos: FakeActivityKudosRepository,
        changes: ActivityChanges = ActivityChanges()
    ) -> ActivityDetailStore {
        let details = FakeActivityDetailRepository(.success(detail))
        return ActivityDetailStore(
            id: detail.id,
            loadDetail: LoadActivityDetail(repository: details),
            loadKudos: LoadKudosList(repository: kudos),
            setKudos: SetActivityKudos(repository: kudos),
            changes: changes,
            updateActivity: UpdateActivity(repository: details),
            deleter: .over(details, changes: changes)
        )
    }

    /// Collects what was published until `marker`, published last by the test.
    private func received(_ stream: AsyncStream<ActivityChange>, until marker: ActivityChange) async -> [ActivityChange] {
        var changes: [ActivityChange] = []
        for await change in stream {
            if change == marker { break }
            changes.append(change)
        }
        return changes
    }

    @Test func theRowShowsTheFiveMostRecentGivers() async {
        let detail = ActivityDetail.fixture(viewerIsAuthor: false)
        let givers = KudosGiver.fixtures(0 ..< 7)
        let kudos = FakeActivityKudosRepository(.success(KudosPage(givers: givers, nextCursor: "next")))
        let store = makeStore(detail, kudos: kudos)

        await store.load()

        #expect(store.recentKudos == Array(givers.prefix(5)))
        #expect(kudos.pageRequests == [.init(activityId: detail.id, cursor: nil, limit: 5)])
    }

    @Test func theKudosButtonIsHiddenOnMyOwnActivity() async {
        let kudos = FakeActivityKudosRepository(.success(KudosPage(givers: KudosGiver.fixtures(0 ..< 2), nextCursor: nil)))
        let mine = makeStore(.fixture(viewerIsAuthor: true), kudos: kudos)
        await mine.load()

        #expect(!mine.showsKudosButton)
        // The count and the givers are still shown.
        #expect(mine.recentKudos.count == 2)
        await mine.toggleKudos()
        #expect(kudos.setRequests.isEmpty)

        let someoneElses = makeStore(.fixture(viewerIsAuthor: false), kudos: kudos)
        await someoneElses.load()
        #expect(someoneElses.showsKudosButton)
    }

    /// Like `FeedStore.toggleKudos`: the count changes at once, then takes the server's answer;
    /// the row is reloaded so the viewer's own avatar appears.
    @Test func givingKudosIsOptimisticThenTakesTheServerCount() async {
        let detail = ActivityDetail.fixture(
            engagement: ActivityEngagement(kudosCount: 2, commentCount: 1, viewerHasKudoed: false),
            viewerIsAuthor: false
        )
        let me = KudosGiver.fixture(99)
        let kudos = FakeActivityKudosRepository(
            .success(KudosPage(givers: KudosGiver.fixtures(0 ..< 2), nextCursor: nil)),
            .success(KudosPage(givers: [me] + KudosGiver.fixtures(0 ..< 2), nextCursor: nil))
        )
        let changes = ActivityChanges()
        let published = changes.subscribe()
        let store = makeStore(detail, kudos: kudos, changes: changes)
        await store.load()
        let duringRequest = Locked<ActivityEngagement?>(nil)
        kudos.onSetKudos = { [store] given in
            duringRequest.value = await MainActor.run { store.detail?.engagement }
            return KudosState(kudosCount: 10, viewerHasKudoed: given)
        }

        await store.toggleKudos()

        let optimistic = ActivityEngagement(kudosCount: 3, commentCount: 1, viewerHasKudoed: true)
        let confirmed = ActivityEngagement(kudosCount: 10, commentCount: 1, viewerHasKudoed: true)
        #expect(kudos.setRequests == [true])
        #expect(duringRequest.value == optimistic)
        #expect(store.detail?.engagement == confirmed)
        #expect(store.recentKudos.first == me)
        #expect(store.kudosNotice == nil)

        let marker = ActivityChange.deleted(ActivityID())
        changes.publish(marker)
        #expect(await received(published, until: marker) == [
            .updated(detail.post),
            .engagement(detail.id, optimistic),
            .engagement(detail.id, confirmed),
        ])
    }

    @Test func aFailedKudosRollsBackAndTellsTheFeed() async {
        let previous = ActivityEngagement(kudosCount: 4, commentCount: 0, viewerHasKudoed: true)
        let detail = ActivityDetail.fixture(engagement: previous, viewerIsAuthor: false)
        let kudos = FakeActivityKudosRepository(.success(KudosPage(givers: KudosGiver.fixtures(0 ..< 4), nextCursor: nil)))
        kudos.onSetKudos = { _ in throw ActivityDetailError.offline }
        let changes = ActivityChanges()
        let published = changes.subscribe()
        let store = makeStore(detail, kudos: kudos, changes: changes)
        await store.load()

        await store.toggleKudos()

        #expect(kudos.setRequests == [false])
        #expect(store.detail?.engagement == previous)
        #expect(store.recentKudos == KudosGiver.fixtures(0 ..< 4))
        #expect(store.kudosNotice == "Kudos non envoyé : vous êtes hors ligne.")

        let marker = ActivityChange.deleted(ActivityID())
        changes.publish(marker)
        #expect(await received(published, until: marker) == [
            .updated(detail.post),
            .engagement(detail.id, ActivityEngagement(kudosCount: 3, commentCount: 0, viewerHasKudoed: false)),
            .engagement(detail.id, previous),
        ])
    }

    /// The givers row is a bonus: when it cannot load, the detail is still shown.
    @Test func theDetailShowsEvenWhenTheKudosRowFails() async {
        let detail = ActivityDetail.fixture(viewerIsAuthor: false)
        let store = makeStore(detail, kudos: FakeActivityKudosRepository(.failure(.network)))

        await store.load()

        #expect(store.phase == .loaded(detail))
        #expect(store.recentKudos.isEmpty)
    }

    /// Back on the feed, the card shows the count given on the detail (ADR-034 §6).
    @Test func theFeedCardShowsTheKudosGivenOnTheDetail() async {
        let post = ActivityPost.fixture(kudos: 2)
        let feedRepository = FakeFeedRepository()
        feedRepository.pages[nil] = .success(FeedPage(posts: [post], nextCursor: nil))
        let changes = ActivityChanges()
        let feed = FeedStore(
            loadFeed: LoadFeed(repository: feedRepository),
            toggleKudos: ToggleKudos(repository: feedRepository),
            events: FakeFeedEventSource(),
            activityChanges: changes
        )
        await feed.refresh()
        let detail = ActivityDetail.fixture(
            id: post.id,
            engagement: post.engagement,
            viewerIsAuthor: false
        )
        let kudos = FakeActivityKudosRepository()
        kudos.onSetKudos = { given in KudosState(kudosCount: 3, viewerHasKudoed: given) }
        let store = makeStore(detail, kudos: kudos, changes: changes)
        await store.load()

        await store.toggleKudos()

        #expect(await eventually { feed.posts.first?.engagement.kudosCount == 3 })
        #expect(feed.posts.first?.engagement.viewerHasKudoed == true)
    }
}
