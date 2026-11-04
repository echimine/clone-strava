import Foundation
import Testing
@testable import StravaClone

/// "Enregistrer" in "Modifier" (ADR-037 §8, #184): a Media still being sent takes its new index
/// and confirms with it; a confirmed Media is deleted. In `MediaUploadQueueTests` (serialized):
/// same network stub.
extension MediaUploadQueueTests {
    @Test func aMediaBeingSentTakesItsNewIndexAmongTheConfirmedOnesAndConfirmsWithIt() async throws {
        let harness = try MediaUploadHarness()
        let transfer = FakeMediaTransfer()
        let photoID = Locked<UUID?>(nil)
        MediaUploadHarness.route { step in
            step == "upload-urls" ? MediaUploadHarness.uploadURLs() : MediaUploadHarness.confirmed(photoID.value!)
        }
        let queue = harness.makeQueue(transfer: transfer)
        let first = ActivityMedia.fixture(), second = ActivityMedia.fixture()
        let photo = MediaUploadHarness.photo()
        photoID.value = photo.id
        await queue.enqueue([QueuedMedia(media: photo, position: 2)], to: harness.activityID)
        #expect(await eventually { transfer.started.count == 2 })

        // "Mettre en premier" on the photo being sent, then "Modifier l'ordre": photo, second, first.
        await queue.reorder([photo.id, second.id, first.id], of: harness.activityID)

        #expect(try await harness.store.upload(photo.id)?.position == 0)
        let shown = queue.board.media(of: harness.activityID, merging: [second, first])
        #expect(shown.map(\.id) == [photo.id, second.id, first.id])
        for put in transfer.started {
            await queue.handle(.finished(put.key, status: 200))
        }
        #expect(try harness.lastBody("media")?["position"] as? Int == 0)
        #expect(queue.board.media(of: harness.activityID, merging: [second, first]).map(\.id) == [photo.id, second.id, first.id])
    }

    @Test func aRowSavedFromAnOlderCopyKeepsItsNewIndex() async throws {
        let harness = try MediaUploadHarness()
        let upload = MediaUpload(
            mediaID: UUID(), activityID: harness.activityID, kind: .photo, position: 0, state: .uploading,
            failure: nil, files: [], attempts: 0, nextAttemptAt: MediaUploadHarness.now, createdAt: MediaUploadHarness.now
        )
        try await harness.store.insert([upload])

        try await harness.store.reposition([upload.mediaID: 3])
        var older = upload
        older.attempts = 1
        try await harness.store.save(older)

        let stored = try await harness.store.upload(upload.mediaID)
        #expect(stored?.position == 3)
        #expect(stored?.attempts == 1)
    }

    @Test func deletingAConfirmedMediaCallsTheAPIAndForgetsIt() async throws {
        let harness = try MediaUploadHarness()
        MediaUploadHarness.route { _ in (204, "") }
        let queue = harness.makeQueue(transfer: FakeMediaTransfer())
        let media = ActivityMedia.fixture()
        queue.board.confirm(media, position: 0, of: harness.activityID)

        let deleted = await queue.deleteConfirmed(media.id, of: harness.activityID)

        #expect(deleted)
        let request = try #require(MediaURLProtocolStub.requests.value.last)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/v1/activities/\(harness.activityID)/media/\(media.id.uuidString.lowercased())")
        #expect(queue.board.media(of: harness.activityID, merging: []).isEmpty)
    }

    @Test func aDeleteThatDoesNotGoThroughIsReported() async throws {
        let harness = try MediaUploadHarness()
        MediaUploadHarness.route { _ in (0, "") }
        let queue = harness.makeQueue(transfer: FakeMediaTransfer())

        #expect(await queue.deleteConfirmed(UUID(), of: harness.activityID) == false)
    }
}
