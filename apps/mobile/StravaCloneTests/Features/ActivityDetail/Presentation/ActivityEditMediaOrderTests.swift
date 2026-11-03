import Foundation
import Testing
@testable import StravaClone

/// "Enregistrer" after "Mettre en premier", "Supprimer" or "Modifier l'ordre" (ADR-037 §8,
/// §10, §13): one `PATCH` with the full order, a confirmed Media deleted, one still being sent
/// discarded, one `activity_media_saved`; nothing at all for an unchanged session.
@MainActor
struct ActivityEditMediaOrderTests {
    private final class Calls {
        var discarded: [UUID] = []
        var reordered: [[UUID]] = []
        var deleted: [UUID] = []
        var deleteSucceeds = true
    }

    private let first = ActivityMedia.fixture(), second = ActivityMedia.fixture()
    private let sending = MediaUploadBoard.Entry(position: 2, media: {
        var media = ActivityMedia.fixture()
        media.upload = .sending(progress: 0.4)
        return media
    }())

    private let previous: ActivityDetail

    init() {
        var detail = ActivityDetail.fixture()
        detail.media = [first, second]
        previous = detail
    }

    private func makeEditor(
        _ repository: FakeActivityDetailRepository,
        analytics: FakeAnalyticsClient,
        calls: Calls
    ) -> ActivityEditor {
        let board = MediaUploadBoard()
        board.show([previous.id: [sending]])
        return ActivityEditor(
            loadDetail: LoadActivityDetail(repository: repository),
            updateActivity: UpdateActivity(repository: repository),
            changes: ActivityChanges(),
            mediaUploads: ActivityMediaUploads(
                board: board,
                enqueue: { _, _ in },
                discard: { calls.discarded += $0 },
                reorder: { order, _ in calls.reordered.append(order) },
                delete: { mediaID, _ in
                    calls.deleted.append(mediaID)
                    return calls.deleteSucceeds
                },
                analytics: analytics
            )
        )
    }

    @Test func anUnchangedSessionSendsNeitherAPatchNorAnEvent() async throws {
        let repository = FakeActivityDetailRepository(.success(previous))
        let analytics = FakeAnalyticsClient()
        let calls = Calls()
        let editor = makeEditor(repository, analytics: analytics, calls: calls)
        editor.edit(previous)

        await editor.save(try #require(editor.form))

        #expect(editor.form == nil)
        #expect(repository.updates.isEmpty)
        #expect(analytics.events.isEmpty)
        #expect(calls.reordered.isEmpty && calls.deleted.isEmpty)
    }

    @Test func aReorderMixingConfirmedAndSendingMediaIsOnePatchWithTheFullOrder() async throws {
        let repository = FakeActivityDetailRepository(.success(previous))
        let analytics = FakeAnalyticsClient()
        let calls = Calls()
        let editor = makeEditor(repository, analytics: analytics, calls: calls)
        editor.edit(previous)
        var form = try #require(editor.form)
        #expect(form.media.order == [first.id, second.id, sending.media.id])

        form.media.putFirst(sending.media.id)
        form.media.move(fromOffsets: IndexSet(integer: 2), toOffset: 1)
        await editor.save(form)

        let order = [sending.media.id, second.id, first.id]
        #expect(calls.reordered == [order])
        #expect(repository.updates.count == 1)
        #expect(repository.updates.first?.edit.mediaOrder == order)
        #expect(repository.updates.first?.edit.mediaFirst == true)
        #expect(analytics.events == [.activityMediaSaved(entry: .edit, ActivityMediaSaved(
            photosAdded: 0, videosAdded: 0, videosTrimmed: 0, mediaRemoved: 0, mediaFirst: true, mediaCount: 3
        ))])
    }

    @Test func removingDeletesAConfirmedMediaAndDiscardsOneBeingSentBeforeThePatch() async throws {
        let repository = FakeActivityDetailRepository(.success(previous))
        let calls = Calls()
        let editor = makeEditor(repository, analytics: FakeAnalyticsClient(), calls: calls)
        editor.edit(previous)
        var form = try #require(editor.form)

        form.media.remove(first.id)
        form.media.remove(sending.media.id)
        await editor.save(form)

        #expect(calls.deleted == [first.id])
        #expect(calls.discarded == [sending.media.id])
        #expect(repository.updates.first?.edit.mediaOrder == [second.id])
        #expect(repository.updates.first?.edit.mediaFirst == false)
        #expect(editor.toast == nil)
    }

    @Test func theOptimisticDetailShowsTheNewOrderAtOnce() async throws {
        let repository = FakeActivityDetailRepository(.success(previous))
        let (gate, open) = AsyncStream.makeStream(of: Void.self)
        repository.updateGate = gate
        let editor = makeEditor(repository, analytics: FakeAnalyticsClient(), calls: Calls())
        var shown: [ActivityDetail] = []
        editor.onChange = { shown.append($0) }
        editor.edit(previous)
        var form = try #require(editor.form)
        form.media.putFirst(second.id)

        let saving = Task { await editor.save(form) }
        #expect(await eventually { repository.updates.count == 1 })

        #expect(shown.first?.media.map(\.id) == [second.id, first.id])
        #expect(shown.first?.mediaFirst == true)
        open.yield()
        await saving.value
    }

    @Test func aDeleteThatDoesNotGoThroughShowsAToast() async throws {
        let repository = FakeActivityDetailRepository(.success(previous))
        let calls = Calls()
        calls.deleteSucceeds = false
        let editor = makeEditor(repository, analytics: FakeAnalyticsClient(), calls: calls)
        editor.edit(previous)
        var form = try #require(editor.form)

        form.media.remove(second.id)
        await editor.save(form)

        #expect(repository.updates.count == 1)
        #expect(editor.toast == ActivityDetailMessages.mediaDeleteFailed)
    }
}
