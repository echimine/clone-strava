import Foundation
import Testing
@testable import StravaClone

/// The comment thread and the feed (ADR-034 §6, ADR-036 §8): the card's comment button opens the
/// Kudos and comments screen on Commentaires, and the card shows the right count when the
/// athlete comes back.
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

    /// Sent, edited and deleted from the screen the card's comment button opened.
    @Test func backFromTheCommentsTheCardShowsTheNewCommentCount() async throws {
        let post = ActivityPost.fixture()
        let changes = ActivityChanges()
        let feed = await makeFeed(post, changes: changes)
        let engagement = ActivityEngagement(kudosCount: 4, commentCount: 1, viewerHasKudoed: true)
        let detail = ActivityDetail.fixture(id: post.id, engagement: engagement)
        let repository = FakeActivityCommentRepository()
        let existing = ActivityComment.fixture(mine: true)
        repository.setPage(.success(ActivityCommentsPage(items: [existing], previousCursor: nil)))

        feed.openComments(post.id)
        let screen = ActivityEngagementStore.over(
            .comments(post.id),
            FakeActivityDetailRepository(.success(detail)),
            comments: repository,
            changes: changes
        )
        await screen.load()
        let comments = screen.comments
        await comments.load()

        comments.draft = "Premier !"
        await comments.send()
        comments.draft = "Deuxième"
        await comments.send()
        let second = try #require(comments.comments.last?.id)
        comments.startEditing(second)
        comments.draft = "Deuxième, modifié"
        await comments.send()
        comments.requestDeletion(existing.id)
        await comments.confirmDeletion()
        feed.path.removeLast()

        let expected = ActivityEngagement(kudosCount: 4, commentCount: 2, viewerHasKudoed: true)
        #expect(screen.detail.detail?.engagement == expected)
        #expect(screen.commentsTitle == "Commentaires · 2")
        #expect(await eventually { feed.posts.first?.engagement == expected })
    }

    /// Without the viewer's own name, a comment being sent shows the Activity's author when the
    /// viewer wrote the Activity (in practice the only commenter until follows exist).
    @Test func aCommentBeingSentShowsTheViewerAsItsAuthor() async throws {
        let detail = ActivityDetail.fixture(viewerIsAuthor: true)
        let repository = FakeActivityCommentRepository()
        repository.holdNextWrite()
        let screen = ActivityEngagementStore.over(
            .comments(detail.id),
            FakeActivityDetailRepository(.success(detail)),
            comments: repository
        )
        await screen.load()

        screen.comments.draft = "Bravo"
        let send = Task { await screen.comments.send() }
        #expect(await eventually { repository.isHoldingWrite })
        #expect(screen.comments.comments.first?.comment.author == detail.author)
        repository.resume()
        await send.value
    }
}
