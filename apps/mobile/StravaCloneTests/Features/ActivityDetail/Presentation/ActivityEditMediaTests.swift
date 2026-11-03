import Foundation
import Testing
@testable import StravaClone

/// "Photos et vidéos" in "Modifier" (ADR-037 §5, §10): the sheet counts the Media being sent,
/// and "Enregistrer" queues the picked photos at their index and sends the full order.
@MainActor
struct ActivityEditMediaTests {
    private let previous = ActivityDetail.fixture(title: "Sortie du matin", sport: .run)

    private func makeEditor(
        _ repository: FakeActivityDetailRepository,
        board: MediaUploadBoard,
        queued: Locked<[(UUID, Int, ActivityID)]>
    ) -> ActivityEditor {
        ActivityEditor(
            loadDetail: LoadActivityDetail(repository: repository),
            updateActivity: UpdateActivity(repository: repository),
            changes: ActivityChanges(),
            mediaUploads: ActivityMediaUploads(board: board) { picked, activityID in
                queued.value += picked.map { ($0.media.id, $0.position, activityID) }
            }
        )
    }

    private func sendingMedia(position: Int) -> MediaUploadBoard.Entry {
        MediaUploadBoard.Entry(position: position, media: ActivityMedia(
            id: UUID(), kind: .photo, width: 1_200, height: 900, duration: nil,
            url: URL(fileURLWithPath: "/tmp/original.jpg"), posterURL: nil,
            thumbURL: URL(fileURLWithPath: "/tmp/thumb.jpg"), upload: .sending(progress: 0.4)
        ))
    }

    @Test func theSheetCountsTheMediaStillBeingSent() {
        let board = MediaUploadBoard()
        let sending = sendingMedia(position: 0)
        board.show([previous.id: [sending]])
        let editor = makeEditor(FakeActivityDetailRepository(.success(previous)), board: board, queued: Locked([]))

        editor.edit(previous)

        #expect(editor.form?.media.order == [sending.media.id])
        #expect(editor.form?.media.remaining == 7)
    }

    @Test func savingQueuesThePickedPhotosAfterTheOthersAndSendsTheFullOrder() async throws {
        let board = MediaUploadBoard()
        let sending = sendingMedia(position: 0)
        board.show([previous.id: [sending]])
        let repository = FakeActivityDetailRepository(.success(previous))
        let queued = Locked<[(UUID, Int, ActivityID)]>([])
        let editor = makeEditor(repository, board: board, queued: queued)
        editor.edit(previous)
        var form = try #require(editor.form)
        let photos = [MediaUploadHarness.photo(Data()), MediaUploadHarness.photo(Data())]
        form.media.add(photos)

        await editor.save(form)

        #expect(editor.form == nil)
        #expect(queued.value.map(\.0) == photos.map(\.id))
        #expect(queued.value.map(\.1) == [1, 2])
        #expect(queued.value.allSatisfy { $0.2 == previous.id })
        #expect(repository.updates.last?.edit.mediaOrder == [sending.media.id] + photos.map(\.id))
    }

    @Test func savingWithoutNewMediaQueuesNothingAndSendsNoOrder() async throws {
        let repository = FakeActivityDetailRepository(.success(previous))
        let queued = Locked<[(UUID, Int, ActivityID)]>([])
        let editor = makeEditor(repository, board: MediaUploadBoard(), queued: queued)
        editor.edit(previous)

        await editor.save(try #require(editor.form))

        #expect(queued.value.isEmpty)
        #expect(repository.updates.last?.edit.mediaOrder == nil)
    }
}
