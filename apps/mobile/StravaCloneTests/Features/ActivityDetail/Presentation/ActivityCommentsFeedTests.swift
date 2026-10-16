import Foundation
import Testing
@testable import StravaClone

/// The comment thread and the feed (ADR-034 §6): the card's comment button opens the detail
/// with the composer focused, and the card shows the right count when the athlete comes back.
@MainActor
struct ActivityCommentsFeedTests {
    private func makeFeed(_ post: ActivityPost, changes: ActivityChanges) async -> FeedStore {
        let repository = FakeFeedRepository()
        repository.pages[nil] = .success(FeedPage(posts: [post], nextCursor: nil))
        let feed = FeedStore(
            loadFeed: LoadFeed(repository: repository),
            toggleKudos: ToggleKudos(repository: repository),
            events: FakeFeedEventSource(),
            localActivities: FakeLocalActivityFeedSource(),
            activityChanges: changes
        )
        await feed.refresh()
        return feed
    }

    /// The detail and its thread, built from the request the feed pushed, as the app shell does.
    private func openDetail(
        _ request: ActivityDetailRequest,
        _ detail: ActivityDetail,
        comments repository: FakeActivityCommentRepository,
        changes: ActivityChanges
    ) -> (ActivityDetailStore, ActivityCommentsStore) {
        let kudos = FakeActivityKudosRepository()
        let detailStore = ActivityDetailStore(
            id: request.id,
            loadDetail: LoadActivityDetail(repository: FakeActivityDetailRepository(.success(detail))),
            loadKudos: LoadKudosList(repository: kudos),
            setKudos: SetActivityKudos(repository: kudos),
            changes: changes
        )
        let comments = ActivityCommentsStore.forDetail(
            detailStore,
            request: request,
            useCases: ActivityCommentUseCases(repository: repository)
        )
        return (detailStore, comments)
    }

    @Test func theCardsCommentButtonOpensTheDetailWithTheComposerFocused() async throws {
        let post = ActivityPost.fixture()
        let changes = ActivityChanges()
        let feed = await makeFeed(post, changes: changes)
        let detail = ActivityDetail.fixture(id: post.id)

        feed.open(post.id, showingComments: true)
        let (_, focused) = openDetail(try #require(feed.path.last), detail, comments: FakeActivityCommentRepository(), changes: changes)
        #expect(focused.isComposerFocused)

        // A tap on the card itself opens the detail without the keyboard.
        feed.path = []
        feed.open(post.id)
        let (_, plain) = openDetail(try #require(feed.path.last), detail, comments: FakeActivityCommentRepository(), changes: changes)
        #expect(!plain.isComposerFocused)
    }

    @Test func backFromTheDetailTheCardShowsTheNewCommentCount() async throws {
        let post = ActivityPost.fixture()
        let changes = ActivityChanges()
        let feed = await makeFeed(post, changes: changes)
        let engagement = ActivityEngagement(kudosCount: 4, commentCount: 1, viewerHasKudoed: true)
        let detail = ActivityDetail.fixture(id: post.id, engagement: engagement)
        let repository = FakeActivityCommentRepository()
        let existing = ActivityComment.fixture(mine: true)
        repository.setPage(.success(ActivityCommentsPage(items: [existing], previousCursor: nil)))

        feed.open(post.id, showingComments: true)
        let (detailStore, comments) = openDetail(try #require(feed.path.last), detail, comments: repository, changes: changes)
        await detailStore.load()
        await comments.load()

        comments.draft = "Premier !"
        await comments.send()
        comments.draft = "Deuxième"
        await comments.send()
        comments.requestDeletion(existing.id)
        await comments.confirmDeletion()
        feed.path = []

        let expected = ActivityEngagement(kudosCount: 4, commentCount: 2, viewerHasKudoed: true)
        #expect(detailStore.detail?.engagement == expected)
        #expect(await eventually { feed.posts.first?.engagement == expected })
    }

    /// Without the viewer's own name, a comment being sent shows the Activity's author when the
    /// viewer wrote the Activity (in practice the only commenter until follows exist).
    @Test func aCommentBeingSentShowsTheViewerAsItsAuthor() async throws {
        let detail = ActivityDetail.fixture(viewerIsAuthor: true)
        let repository = FakeActivityCommentRepository()
        repository.holdNextWrite()
        let (detailStore, comments) = openDetail(ActivityDetailRequest(id: detail.id), detail, comments: repository, changes: ActivityChanges())
        await detailStore.load()

        comments.draft = "Bravo"
        let send = Task { await comments.send() }
        #expect(await eventually { repository.isHoldingWrite })
        #expect(comments.comments.first?.comment.author == detail.author)
        repository.resume()
        await send.value
    }
}
