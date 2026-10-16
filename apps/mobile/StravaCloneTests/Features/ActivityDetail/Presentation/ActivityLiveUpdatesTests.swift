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
            changes: ActivityChanges(),
            updateActivity: UpdateActivity(repository: details),
            deleter: .over(details)
        )
        let comments = ActivityCommentsStore.forDetail(
            detail,
            request: ActivityDetailRequest(id: id),
            repository: commentsRepository
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
        await processed(screen, comments)

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

    /// Older comments not loaded yet: an edit of one of them is not this thread's to show,
    /// and never changes the count.
    @Test func anEditOfACommentNotLoadedChangesNeitherTheThreadNorTheCount() async {
        let activity = ActivityDetail.fixture(engagement: ActivityEngagement(kudosCount: 0, commentCount: 3, viewerHasKudoed: false))
        let comments = FakeActivityCommentRepository()
        let newest = ActivityComment.fixture(body: "Dernier")
        comments.setPage(.success(ActivityCommentsPage(items: [newest], previousCursor: "c1")))
        let screen = await openScreen(FakeActivityDetailRepository(.success(activity)), comments: comments, id: activity.id)
        let older = UUID()

        screen.source.send(.commentUpdated(older))
        await processed(screen, comments)

        #expect(screen.comments.comments.map(\.comment) == [newest])
        #expect(screen.detail.detail?.engagement.commentCount == 3)
        #expect(!comments.calls.contains(.one(older)))
        screen.live.cancel()
    }

    /// A comment of an older page, deleted elsewhere: nothing to remove, one comment less all
    /// the same.
    @Test func aCommentNotLoadedDeletedElsewhereLowersTheCount() async {
        let activity = ActivityDetail.fixture(engagement: ActivityEngagement(kudosCount: 0, commentCount: 3, viewerHasKudoed: false))
        let comments = FakeActivityCommentRepository()
        let newest = ActivityComment.fixture(body: "Dernier")
        comments.setPage(.success(ActivityCommentsPage(items: [newest], previousCursor: "c1")))
        let screen = await openScreen(FakeActivityDetailRepository(.success(activity)), comments: comments, id: activity.id)

        screen.source.send(.commentDeleted(UUID()))

        #expect(await eventually { screen.detail.detail?.engagement.commentCount == 2 })
        #expect(screen.comments.comments.map(\.comment) == [newest])
        screen.live.cancel()
    }

    /// My delete comes back as `comment.deleted`: the count already went down once.
    @Test func theEchoOfMyOwnDeleteIsNotCountedTwice() async {
        let activity = ActivityDetail.fixture(engagement: ActivityEngagement(kudosCount: 0, commentCount: 2, viewerHasKudoed: false))
        let comments = FakeActivityCommentRepository()
        let mine = ActivityComment.fixture(body: "À supprimer", mine: true)
        let other = ActivityComment.fixture(body: "Reste", createdAt: Date(timeIntervalSince1970: 1_790_000_060))
        comments.setPage(.success(ActivityCommentsPage(items: [mine, other], previousCursor: nil)))
        let screen = await openScreen(FakeActivityDetailRepository(.success(activity)), comments: comments, id: activity.id)
        screen.comments.requestDeletion(mine.id)
        await screen.comments.confirmDeletion()

        screen.source.send(.commentDeleted(mine.id))
        await processed(screen, comments)

        #expect(screen.comments.comments.map(\.comment) == [other])
        #expect(screen.detail.detail?.engagement.commentCount == 1)
        screen.live.cancel()
    }

    /// A comment fetched after its `comment.created` but gone by then: its `comment.deleted`
    /// does not take it off the count, which never had it.
    @Test func aCommentGoneBeforeItCouldBeFetchedIsNotCountedOut() async {
        let activity = ActivityDetail.fixture(engagement: ActivityEngagement(kudosCount: 0, commentCount: 1, viewerHasKudoed: false))
        let comments = FakeActivityCommentRepository()
        let kept = ActivityComment.fixture(body: "Reste")
        comments.setPage(.success(ActivityCommentsPage(items: [kept], previousCursor: nil)))
        let screen = await openScreen(FakeActivityDetailRepository(.success(activity)), comments: comments, id: activity.id)
        let gone = UUID()
        comments.scriptOne(.failure(.notFound))

        screen.source.send(.commentCreated(gone))
        screen.source.send(.commentDeleted(gone))
        await processed(screen, comments)

        #expect(screen.comments.comments.map(\.comment) == [kept])
        #expect(screen.detail.detail?.engagement.commentCount == 1)
        screen.live.cancel()
    }

    /// My edit comes back as `comment.updated`, before or after the `PATCH` answers: the thread
    /// already shows that text, so it is not fetched.
    @Test(arguments: [true, false])
    func theEchoOfMyOwnEditIsNotFetched(beforeTheAnswer: Bool) async {
        let activity = ActivityDetail.fixture(engagement: ActivityEngagement(kudosCount: 0, commentCount: 1, viewerHasKudoed: false))
        let comments = FakeActivityCommentRepository()
        let mine = ActivityComment.fixture(body: "Belle sortie", author: comments.author, mine: true)
        comments.setPage(.success(ActivityCommentsPage(items: [mine], previousCursor: nil)))
        let screen = await openScreen(FakeActivityDetailRepository(.success(activity)), comments: comments, id: activity.id)
        screen.comments.startEditing(mine.id)
        screen.comments.draft = "Belle sortie au lac"
        comments.holdNextWrite()
        let editing = Task { await screen.comments.send() }
        #expect(await eventually { comments.isHoldingWrite })

        if beforeTheAnswer {
            screen.source.send(.commentUpdated(mine.id))
            await processed(screen, comments)
        }
        comments.resume()
        await editing.value
        if !beforeTheAnswer {
            screen.source.send(.commentUpdated(mine.id))
            await processed(screen, comments)
        }

        #expect(!comments.calls.contains(.one(mine.id)))
        #expect(screen.comments.comments.map(\.comment.body) == ["Belle sortie au lac"])
        #expect(screen.detail.detail?.engagement.commentCount == 1)
        screen.live.cancel()
    }

    /// Waits until the events sent so far are handled: a marker sent after them is fetched
    /// (and not found).
    private func processed(_ screen: Screen, _ comments: FakeActivityCommentRepository) async {
        let marker = UUID()
        screen.source.send(.commentCreated(marker))
        _ = await eventually { comments.calls.contains(.one(marker)) }
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
