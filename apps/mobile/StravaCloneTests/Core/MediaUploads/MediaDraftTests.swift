import Foundation
import Testing
@testable import StravaClone

/// The "Photos et vidéos" section of "Modifier" (ADR-037 §10) and the merge of the Media being
/// sent into the author's carousel (§5).
@MainActor
struct MediaDraftTests {
    private func media(_ upload: MediaUploadStatus? = nil) -> ActivityMedia {
        ActivityMedia(
            id: UUID(), kind: .photo, width: 2_048, height: 1_536, duration: nil,
            url: URL(string: "https://bucket.test/\(UUID()).jpg")!, posterURL: nil,
            thumbURL: URL(string: "https://bucket.test/thumb.jpg")!, upload: upload
        )
    }

    @Test func thePickerIsLimitedToWhatRemainsCountingTheMediaBeingSent() {
        var draft = MediaDraft(media: [media(), media(), media(.sending(progress: 0.3))], hasMap: true, mediaFirst: false)
        #expect(draft.remaining == 5)

        draft.add((0 ..< 7).map { _ in MediaUploadHarness.photo(Data()) })

        #expect(draft.count == 8)
        #expect(draft.remaining == 0)
        #expect(draft.added.count == 5)
    }

    @Test func theNewMediaGoAfterTheOthersAndTheOrderIncludesThemAll() {
        let first = media()
        let sending = media(.sending(progress: 0.5))
        var draft = MediaDraft(media: [first, sending], hasMap: true, mediaFirst: true)
        let picked = [MediaUploadHarness.photo(Data()), MediaUploadHarness.photo(Data())]

        draft.add(picked)

        #expect(draft.queued.map(\.media.id) == picked.map(\.id))
        #expect(draft.queued.map(\.position) == [2, 3])
        #expect(draft.order == [first.id, sending.id] + picked.map(\.id))
        #expect(draft.slides.map(\.id) == [.media(first.id), .map, .media(sending.id)] + picked.map { .media($0.id) })
    }

    @Test func anUnchangedSessionHasNoChanges() {
        let draft = MediaDraft(media: [media()], hasMap: false, mediaFirst: false)

        #expect(!draft.hasChanges)
        #expect(draft.slides.count == 1)
    }

    @Test func aLocalMediaTakesItsIndexAmongTheConfirmedOnes() {
        let a = media(), b = media(), c = media()
        let local = media(.sending(progress: 0))

        let merged = MediaUploadBoard.merge(remote: [a, b, c], local: [MediaUploadBoard.Entry(position: 1, media: local)])

        #expect(merged.map(\.id) == [a.id, local.id, b.id, c.id])
    }

    @Test func aLocalMediaTheAPIAlreadyReturnsIsNotShownTwice() {
        let confirmed = media()
        var local = confirmed
        local.upload = .sending(progress: 1)

        let merged = MediaUploadBoard.merge(remote: [confirmed], local: [MediaUploadBoard.Entry(position: 0, media: local)])

        #expect(merged == [confirmed])
    }

    @Test func anotherAthletesActivityIsLeftAsTheAPIReturnsIt() {
        let board = MediaUploadBoard()
        let remote = [media()]

        #expect(board.media(of: ActivityID(), merging: remote) == remote)
    }
}
