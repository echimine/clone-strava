import Foundation
import Testing
@testable import StravaClone

/// The live detail (ADR-034 §5): while it is open, the Activity's events reach its stores; a
/// reconnection reloads what may have been missed.
@MainActor
struct ActivityLiveUpdatesTests {
    /// The detail's screen: its stores, their fakes, and the live updates running like the
    /// page's `.task`.
    private struct Screen {
        let detail: ActivityDetailStore
        let comments: ActivityCommentsStore
        let details: FakeActivityDetailRepository
        let kudos: FakeActivityKudosRepository
        let commentsRepository: FakeActivityCommentRepository
        let source: FakeActivityLiveEventSource
        let live: Task<Void, Never>
    }

    private func openScreen(
        _ details: FakeActivityDetailRepository,
        kudos: FakeActivityKudosRepository = FakeActivityKudosRepository(),
        comments commentsRepository: FakeActivityCommentRepository = FakeActivityCommentRepository(),
        id: ActivityID
    ) async -> Screen {
        let detail = ActivityDetailStore(
            id: id,
            loadDetail: LoadActivityDetail(repository: details),
            loadKudos: LoadKudosList(repository: kudos),
            setKudos: SetActivityKudos(repository: kudos),
            changes: ActivityChanges()
        )
        let comments = ActivityCommentsStore.forDetail(
            detail,
            request: ActivityDetailRequest(id: id),
            useCases: ActivityCommentUseCases(repository: commentsRepository)
        )
        await detail.load()
        await comments.load()
        let source = FakeActivityLiveEventSource()
        let updates = ActivityLiveUpdates(events: source, detail: detail, comments: comments)
        let live = Task { await updates.run() }
        _ = await eventually { source.subscribedIds == [id] }
        return Screen(
            detail: detail,
            comments: comments,
            details: details,
            kudos: kudos,
            commentsRepository: commentsRepository,
            source: source,
            live: live
        )
    }

    @Test func subscribesWhileTheDetailIsOpenOnly() async {
        let activity = ActivityDetail.fixture()
        let screen = await openScreen(FakeActivityDetailRepository(.success(activity)), id: activity.id)
        #expect(screen.source.subscribedIds == [activity.id])

        screen.live.cancel()

        #expect(await eventually { screen.source.subscribedIds.isEmpty })
    }

    /// Back after a disconnection: the detail, its kudos row and its comments are read again.
    @Test func reloadsTheDetailAndTheCommentsAfterAReconnection() async {
        let activity = ActivityDetail.fixture(title: "Avant")
        let renamed = ActivityDetail.fixture(id: activity.id, title: "Après")
        let comments = FakeActivityCommentRepository()
        let missed = ActivityComment.fixture(body: "Pendant la coupure")
        let screen = await openScreen(
            FakeActivityDetailRepository(.success(activity), .success(renamed)),
            comments: comments,
            id: activity.id
        )
        comments.setPage(.success(ActivityCommentsPage(items: [missed], previousCursor: nil)))

        screen.source.send(.reconnected)

        #expect(await eventually { screen.detail.detail?.title == "Après" })
        #expect(await eventually { screen.comments.comments.map(\.comment) == [missed] })
        #expect(screen.kudos.pageRequests.count == 2)
        screen.live.cancel()
    }

    // MARK: Comments

    @Test func aCommentPostedElsewhereIsFetchedThenShownInOrder() async {
        let activity = ActivityDetail.fixture(engagement: ActivityEngagement(kudosCount: 0, commentCount: 1, viewerHasKudoed: false))
        let comments = FakeActivityCommentRepository()
        let first = ActivityComment.fixture(body: "Premier", createdAt: Date(timeIntervalSince1970: 1_790_000_000))
        comments.setPage(.success(ActivityCommentsPage(items: [first], previousCursor: nil)))
        let screen = await openScreen(FakeActivityDetailRepository(.success(activity)), comments: comments, id: activity.id)
        let posted = ActivityComment.fixture(body: "Bravo !", createdAt: Date(timeIntervalSince1970: 1_790_000_060))
        comments.scriptOne(.success(posted))

        screen.source.send(.commentCreated(posted.id))

        #expect(await eventually { screen.comments.comments.map(\.comment) == [first, posted] })
        #expect(comments.calls.last == .one(posted.id))
        #expect(screen.detail.detail?.engagement.commentCount == 2)
        screen.live.cancel()
    }

    /// My own comment comes back as `comment.created`, possibly before the `POST` answers: it
    /// is known by its app-generated id, so it is neither fetched nor shown twice.
    @Test func theEchoOfMyOwnCommentDoesNotDuplicateIt() async throws {
        let activity = ActivityDetail.fixture(engagement: ActivityEngagement(kudosCount: 0, commentCount: 0, viewerHasKudoed: false))
        let comments = FakeActivityCommentRepository()
        let screen = await openScreen(FakeActivityDetailRepository(.success(activity)), comments: comments, id: activity.id)
        comments.holdNextWrite()
        screen.comments.draft = "Super sortie"
        let sending = Task { await screen.comments.send() }
        #expect(await eventually { comments.isHoldingWrite })
        let id = try #require(screen.comments.comments.first?.id)

        screen.source.send(.commentCreated(id))
        comments.resume()
        await sending.value
        screen.source.send(.commentCreated(id))
        screen.source.send(.commentUpdated(UUID())) // a marker: processed after the echoes
        _ = await eventually { comments.calls.count == 3 }

        #expect(screen.comments.comments.map(\.comment.body) == ["Super sortie"])
        #expect(screen.comments.comments.map(\.status) == [.sent])
        #expect(!comments.calls.contains(.one(id)))
        #expect(screen.detail.detail?.engagement.commentCount == 1)
        screen.live.cancel()
    }

    @Test func anEditedCommentIsReplacedAndOneNoLongerFoundIsRemoved() async {
        let activity = ActivityDetail.fixture(engagement: ActivityEngagement(kudosCount: 0, commentCount: 2, viewerHasKudoed: false))
        let comments = FakeActivityCommentRepository()
        let edited = ActivityComment.fixture(body: "Avant")
        let vanished = ActivityComment.fixture(body: "Bientôt parti", createdAt: Date(timeIntervalSince1970: 1_790_000_060))
        comments.setPage(.success(ActivityCommentsPage(items: [edited, vanished], previousCursor: nil)))
        let screen = await openScreen(FakeActivityDetailRepository(.success(activity)), comments: comments, id: activity.id)
        var after = edited
        after.body = "Après"
        after.updatedAt = Date(timeIntervalSince1970: 1_790_000_120)
        comments.scriptOne(.success(after), .failure(.notFound))

        screen.source.send(.commentUpdated(edited.id))
        screen.source.send(.commentUpdated(vanished.id))

        #expect(await eventually { screen.comments.comments.map(\.comment) == [after] })
        #expect(screen.detail.detail?.engagement.commentCount == 1)
        screen.live.cancel()
    }

    @Test func aDeletedCommentIsRemovedWithoutAnyRequest() async {
        let activity = ActivityDetail.fixture(engagement: ActivityEngagement(kudosCount: 0, commentCount: 2, viewerHasKudoed: false))
        let comments = FakeActivityCommentRepository()
        let kept = ActivityComment.fixture(body: "Reste")
        let deleted = ActivityComment.fixture(body: "Supprimé", createdAt: Date(timeIntervalSince1970: 1_790_000_060))
        comments.setPage(.success(ActivityCommentsPage(items: [kept, deleted], previousCursor: nil)))
        let screen = await openScreen(FakeActivityDetailRepository(.success(activity)), comments: comments, id: activity.id)

        screen.source.send(.commentDeleted(deleted.id))

        #expect(await eventually { screen.comments.comments.map(\.comment) == [kept] })
        #expect(comments.calls == [.page(before: nil)])
        #expect(screen.detail.detail?.engagement.commentCount == 1)
        screen.live.cancel()
    }

    // MARK: Kudos

    /// Someone gave kudos: the count, `viewerHasKudoed` and the givers' row are read again.
    @Test func kudosGivenElsewhereReloadTheEngagementAndTheRow() async {
        let activity = ActivityDetail.fixture(engagement: ActivityEngagement(kudosCount: 0, commentCount: 0, viewerHasKudoed: false))
        let kudoed = ActivityDetail.fixture(id: activity.id, engagement: ActivityEngagement(kudosCount: 1, commentCount: 0, viewerHasKudoed: false))
        let giver = KudosGiver.fixtures(0 ..< 1)
        let screen = await openScreen(
            FakeActivityDetailRepository(.success(activity), .success(kudoed)),
            kudos: FakeActivityKudosRepository(
                .success(KudosPage(givers: [], nextCursor: nil)),
                .success(KudosPage(givers: giver, nextCursor: nil))
            ),
            id: activity.id
        )

        screen.source.send(.kudosChanged)

        #expect(await eventually { screen.detail.detail?.engagement.kudosCount == 1 })
        #expect(await eventually { screen.detail.recentKudos == giver })
        screen.live.cancel()
    }
}
