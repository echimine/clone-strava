import Foundation
import Testing
@testable import StravaClone

/// A tap on a Media of a carousel opens the viewer on it and sends `media_viewer_opened` with
/// the screen it came from, the Media's kind and whether the Activity is mine (ADR-037 §13).
@MainActor
struct MediaViewerOpenedTests {
    private let photo = ActivityMedia.fixture()
    private let video = ActivityMedia.fixture(kind: .video)

    private func post(viewerIsAuthor: Bool) -> ActivityPost {
        var post = ActivityPost.fixture(viewerIsAuthor: viewerIsAuthor)
        post.media = [photo, video]
        return post
    }

    @Test func fromTheFeed() async {
        let analytics = FakeAnalyticsClient()
        let repository = FakeFeedRepository()
        let post = post(viewerIsAuthor: false)
        repository.pages[nil] = .success(FeedPage(posts: [post], nextCursor: nil))
        let store = FeedStore(
            loadFeed: LoadFeed(repository: repository),
            toggleKudos: ToggleKudos(repository: repository),
            events: FakeFeedEventSource(),
            analytics: analytics
        )
        await store.refresh()

        store.openMedia(video, of: post.id)

        #expect(store.mediaViewer?.start == 1)
        #expect(store.mediaViewer?.position(at: 1) == "2 sur 2")
        #expect(analytics.events == [.mediaViewerOpened(source: .feed, kind: .video, isOwn: false)])
    }

    @Test func fromMyActivitiesTab() async {
        let analytics = FakeAnalyticsClient()
        let athletes = FakeAthleteRepository()
        let post = post(viewerIsAuthor: true)
        athletes.pages[nil] = .success(FeedPage(posts: [post], nextCursor: nil))
        let store = ProfileActivitiesStore(loadActivities: LoadProfileActivities(repository: athletes), analytics: analytics)
        await store.refresh(athleteId: "me")

        store.openMedia(photo, of: post.id)

        #expect(store.mediaViewer?.start == 0)
        #expect(analytics.events == [.mediaViewerOpened(source: .profileActivities, kind: .photo, isOwn: true)])
    }

    @Test func fromAnotherAthletesActivitiesTab() async {
        let analytics = FakeAnalyticsClient()
        let athletes = FakeAthleteRepository()
        let post = post(viewerIsAuthor: false)
        athletes.pages[nil] = .success(FeedPage(posts: [post], nextCursor: nil))
        let store = AthleteActivitiesStore(
            loadActivities: LoadAthleteActivities(repository: athletes),
            setKudos: SetAthleteActivityKudos(repository: FakeAthleteKudosRepository()),
            analytics: analytics
        )
        await store.refresh(athleteId: "lea")

        store.openMedia(video, of: post.id)

        #expect(store.mediaViewer?.start == 1)
        #expect(analytics.events == [.mediaViewerOpened(source: .profileActivities, kind: .video, isOwn: false)])
    }

    @Test func fromTheDetail() async {
        let analytics = FakeAnalyticsClient()
        var detail = ActivityDetail.fixture(viewerIsAuthor: true)
        detail.media = [photo, video]
        let repository = FakeActivityDetailRepository(.success(detail))
        let changes = ActivityChanges()
        let kudos = FakeActivityKudosRepository()
        let store = ActivityDetailStore(
            id: detail.id,
            loadDetail: LoadActivityDetail(repository: repository),
            loadKudos: LoadKudosList(repository: kudos),
            setKudos: SetActivityKudos(repository: kudos),
            changes: changes,
            updateActivity: UpdateActivity(repository: repository),
            deleter: .over(repository, changes: changes),
            analytics: analytics
        )
        await store.load()

        store.openMedia(photo)

        #expect(store.mediaViewer?.items.map(\.media) == [photo, video])
        #expect(analytics.events == [.mediaViewerOpened(source: .detail, kind: .photo, isOwn: true)])
    }

    @Test func aMediaGoneAfterARefreshOpensNothing() async {
        let analytics = FakeAnalyticsClient()
        let repository = FakeFeedRepository()
        let post = post(viewerIsAuthor: false)
        repository.pages[nil] = .success(FeedPage(posts: [post], nextCursor: nil))
        let store = FeedStore(
            loadFeed: LoadFeed(repository: repository),
            toggleKudos: ToggleKudos(repository: repository),
            events: FakeFeedEventSource(),
            analytics: analytics
        )
        await store.refresh()

        store.openMedia(.fixture(), of: post.id)

        #expect(store.mediaViewer == nil)
        #expect(analytics.events.isEmpty)
    }
}
