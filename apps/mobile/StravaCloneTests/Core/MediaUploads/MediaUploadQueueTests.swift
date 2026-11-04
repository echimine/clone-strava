import Foundation
import Testing
@testable import StravaClone

/// A photo's journey from the library to a confirmed Media (ADR-037 §5): the real API adapter
/// over a stubbed network, the real GRDB store in memory, a fake background session; one test
/// per line of the failure table.
@MainActor
@Suite(.serialized)
struct MediaUploadQueueTests {
    init() {
        MediaUploadHarness.resetNetwork()
    }

    /// One photo queued at `position`, exported, its URLs asked for and its `PUT`s started.
    private func sendingPhoto(
        _ harness: MediaUploadHarness,
        transfer: FakeMediaTransfer,
        position: Int = 0
    ) async throws -> (MediaUploadQueue, PickedMedia) {
        let queue = harness.makeQueue(transfer: transfer)
        let photo = MediaUploadHarness.photo()
        await queue.enqueue([QueuedMedia(media: photo, position: position)], to: harness.activityID)
        #expect(await eventually { transfer.started.count == 2 })
        return (queue, photo)
    }

    private func row(_ harness: MediaUploadHarness, _ photo: PickedMedia) async throws -> MediaUpload? {
        try await harness.store.upload(photo.id)
    }

    private func finishAll(_ queue: MediaUploadQueue, _ transfer: FakeMediaTransfer, status: Int = 200) async {
        for put in transfer.started {
            await queue.handle(.finished(put.key, status: status))
        }
    }

    // MARK: - The chain

    @Test func aPickedPhotoIsExportedThenEachFilePutWithItsSignedHeaders() async throws {
        let harness = try MediaUploadHarness()
        MediaUploadHarness.route { _ in MediaUploadHarness.uploadURLs() }
        let transfer = FakeMediaTransfer()

        let (_, photo) = try await sendingPhoto(harness, transfer: transfer, position: 3)

        #expect(harness.requestLines == ["POST upload-urls"])
        let body = try #require(try harness.lastBody("upload-urls"))
        #expect(body["mediaId"] as? String == photo.id.uuidString.lowercased())
        #expect(body["kind"] as? String == "photo")
        let files = try #require(body["files"] as? [[String: Any]])
        #expect(files.map { $0["name"] as? String } == ["original.jpg", "thumb.jpg"])
        let upload = try #require(try await row(harness, photo))
        #expect(upload.state == .uploading)
        #expect(upload.width == 1_200 && upload.height == 900 && upload.position == 3)
        for put in transfer.started {
            let size = try FileManager.default.attributesOfItem(atPath: put.file.path)[.size] as? Int
            #expect(put.contentType == "image/jpeg")
            #expect(put.contentLength == size)
            #expect(put.destination.absoluteString == "https://bucket.test/\(put.key.name)?sig=first")
            #expect(files.first { $0["name"] as? String == put.key.name }?["contentLength"] as? Int == size)
        }
    }

    @Test func bothFilesInTheBucketConfirmTheMediaThenItsRowAndFilesGo() async throws {
        let harness = try MediaUploadHarness()
        let transfer = FakeMediaTransfer()
        let photoID = Locked<UUID?>(nil)
        MediaUploadHarness.route { step in
            step == "upload-urls" ? MediaUploadHarness.uploadURLs() : MediaUploadHarness.confirmed(photoID.value!)
        }
        let (queue, photo) = try await sendingPhoto(harness, transfer: transfer, position: 3)
        photoID.value = photo.id

        await finishAll(queue, transfer)

        #expect(harness.requestLines == ["POST upload-urls", "POST media"])
        let body = try #require(try harness.lastBody("media"))
        #expect(body["id"] as? String == photo.id.uuidString.lowercased())
        #expect(body["kind"] as? String == "photo")
        #expect(body["width"] as? Int == 1_200)
        #expect(body["height"] as? Int == 900)
        #expect(body["position"] as? Int == 3)
        #expect(body["durationMs"] == nil)
        #expect(try await row(harness, photo) == nil)
        #expect(!FileManager.default.fileExists(atPath: harness.files.directory(of: photo.id).path))
        let shown = queue.board.media(of: harness.activityID, merging: [])
        #expect(shown.map(\.id) == [photo.id])
        #expect(shown.first?.upload == nil)
        #expect(shown.first?.url.host == "bucket.test")
    }

    // MARK: - Failure table

    @Test func a403FromTheBucketAsksForNewURLsThenPutsTheFileAgain() async throws {
        let harness = try MediaUploadHarness()
        let calls = Locked(0)
        MediaUploadHarness.route { _ in
            calls.value += 1
            return MediaUploadHarness.uploadURLs(calls.value == 1 ? "first" : "second")
        }
        let transfer = FakeMediaTransfer()
        let (queue, photo) = try await sendingPhoto(harness, transfer: transfer)
        let original = try #require(transfer.started.first { $0.key.name == "original.jpg" })

        await queue.handle(.finished(original.key, status: 403))

        #expect(harness.requestLines == ["POST upload-urls", "POST upload-urls"])
        #expect(transfer.startedNames == ["original.jpg", "thumb.jpg", "original.jpg"])
        #expect(transfer.started.last?.destination.query == "sig=second")
        #expect(try await row(harness, photo)?.state == .uploading)
    }

    @Test func fiveNetworkFailuresInARowTurnTheTileFailed() async throws {
        let harness = try MediaUploadHarness()
        MediaUploadHarness.route { _ in (503, "") }
        let queue = harness.makeQueue(transfer: FakeMediaTransfer())
        let photo = MediaUploadHarness.photo()
        await queue.enqueue([QueuedMedia(media: photo, position: 0)], to: harness.activityID)
        #expect(await eventually { (try? await row(harness, photo))?.attempts == 1 })

        for _ in 0 ..< 3 {
            await queue.send(ignoringBackoff: true)
        }
        #expect(try await row(harness, photo)?.state == .uploading)
        #expect(harness.analytics.names.isEmpty)
        await queue.send(ignoringBackoff: true)

        let failed = try #require(try await row(harness, photo))
        #expect(failed.state == .failed)
        #expect(failed.failure == .network)
        #expect(harness.requestLines.count == 5)
        #expect(harness.analytics.events == [.mediaUploadFailed(kind: .photo, reason: .network)])
        #expect(queue.board.media(of: harness.activityID, merging: []).first?.upload == .failed(.network, canRetry: true))
    }

    @Test func aFailureWaitsForTheBackoffBeforeTheNextAttempt() async throws {
        let harness = try MediaUploadHarness()
        MediaUploadHarness.route { _ in MediaUploadHarness.uploadURLs() }
        let transfer = FakeMediaTransfer()
        let (queue, photo) = try await sendingPhoto(harness, transfer: transfer)
        let original = try #require(transfer.started.first)

        await queue.handle(.finished(original.key, status: 500))

        let postponed = try #require(try await row(harness, photo))
        #expect(postponed.attempts == 1)
        #expect(postponed.nextAttemptAt == MediaUploadHarness.now.addingTimeInterval(2))
        #expect(harness.requestLines == ["POST upload-urls"])
        await queue.send(ignoringBackoff: true)
        #expect(transfer.startedNames == ["original.jpg", "thumb.jpg", "original.jpg"])
    }

    @Test func mediaMissingOnConfirmationSendsTheFilesAgain() async throws {
        let harness = try MediaUploadHarness()
        MediaUploadHarness.route { step in
            step == "upload-urls" ? MediaUploadHarness.uploadURLs() : MediaUploadHarness.refused(409, "media_missing")
        }
        let transfer = FakeMediaTransfer()
        let (queue, photo) = try await sendingPhoto(harness, transfer: transfer)

        await finishAll(queue, transfer)

        #expect(harness.requestLines == ["POST upload-urls", "POST media", "POST upload-urls"])
        #expect(transfer.startedNames == ["original.jpg", "thumb.jpg", "original.jpg", "thumb.jpg"])
        let again = try #require(try await row(harness, photo))
        #expect(again.state == .uploading)
        #expect(again.files.allSatisfy { !$0.uploaded })
        #expect(harness.analytics.names.isEmpty)
    }

    @Test func theLimitOf8FailsAtOnce() async throws {
        let harness = try MediaUploadHarness()
        MediaUploadHarness.route { _ in MediaUploadHarness.refused(409, "media_limit_reached") }
        let transfer = FakeMediaTransfer()
        let queue = harness.makeQueue(transfer: transfer)
        let photo = MediaUploadHarness.photo()

        await queue.enqueue([QueuedMedia(media: photo, position: 0)], to: harness.activityID)

        #expect(await eventually { (try? await row(harness, photo))?.state == .failed })
        #expect(try await row(harness, photo)?.failure == .limitReached)
        #expect(transfer.started.isEmpty)
        #expect(harness.analytics.events == [.mediaUploadFailed(kind: .photo, reason: .limitReached)])
        #expect(harness.analytics.events.first?.properties == ["kind": "photo", "reason": "limit_reached"])
    }

    @Test func aValidationErrorOnConfirmationFailsAtOnceAsInvalid() async throws {
        let harness = try MediaUploadHarness()
        MediaUploadHarness.route { step in
            step == "upload-urls" ? MediaUploadHarness.uploadURLs() : MediaUploadHarness.refused(422, "validation_error")
        }
        let transfer = FakeMediaTransfer()
        let (queue, photo) = try await sendingPhoto(harness, transfer: transfer)

        await finishAll(queue, transfer)

        #expect(try await row(harness, photo)?.failure == .invalid)
        #expect(harness.analytics.events == [.mediaUploadFailed(kind: .photo, reason: .invalid)])
    }

    @Test func anExportThatFailsTurnsTheTileFailed() async throws {
        let harness = try MediaUploadHarness()
        let transfer = FakeMediaTransfer()
        let queue = harness.makeQueue(transfer: transfer)
        let unreadable = MediaUploadHarness.photo(Data("not an image".utf8))

        await queue.enqueue([QueuedMedia(media: unreadable, position: 0)], to: harness.activityID)

        #expect(await eventually { (try? await row(harness, unreadable))?.state == .failed })
        #expect(try await row(harness, unreadable)?.failure == .exportFailed)
        #expect(harness.requestLines.isEmpty)
        #expect(harness.analytics.events == [.mediaUploadFailed(kind: .photo, reason: .exportFailed)])
    }

    @Test func aDeletedActivityAbandonsTheMediaSilently() async throws {
        let harness = try MediaUploadHarness()
        MediaUploadHarness.route { _ in MediaUploadHarness.refused(404, "activity_not_found") }
        let queue = harness.makeQueue(transfer: FakeMediaTransfer())
        let photo = MediaUploadHarness.photo()

        await queue.enqueue([QueuedMedia(media: photo, position: 0)], to: harness.activityID)

        #expect(await eventually { harness.requestLines.count == 1 })
        #expect(await eventually { (try? await row(harness, photo)) == nil })
        #expect(!FileManager.default.fileExists(atPath: harness.files.directory(of: photo.id).path))
        #expect(harness.analytics.names.isEmpty)
        #expect(queue.board.media(of: harness.activityID, merging: []).isEmpty)
    }

    // MARK: - "Réessayer", "Retirer"

    @Test func retryingAFailedTileSendsItsFilesAgain() async throws {
        let harness = try MediaUploadHarness()
        MediaUploadHarness.route { _ in MediaUploadHarness.refused(409, "media_limit_reached") }
        let transfer = FakeMediaTransfer()
        let queue = harness.makeQueue(transfer: transfer)
        let photo = MediaUploadHarness.photo()
        await queue.enqueue([QueuedMedia(media: photo, position: 0)], to: harness.activityID)
        #expect(await eventually { (try? await row(harness, photo))?.state == .failed })
        MediaUploadHarness.route { _ in MediaUploadHarness.uploadURLs() }

        await queue.retry(photo.id)

        #expect(transfer.startedNames == ["original.jpg", "thumb.jpg"])
        #expect(try await row(harness, photo)?.state == .uploading)
    }

    @Test func removingAMediaCancelsItsUploadsAndDeletesItsFiles() async throws {
        let harness = try MediaUploadHarness()
        MediaUploadHarness.route { _ in MediaUploadHarness.uploadURLs() }
        let transfer = FakeMediaTransfer()
        let (queue, photo) = try await sendingPhoto(harness, transfer: transfer)

        await queue.remove(photo.id)

        #expect(transfer.cancelled == [photo.id])
        #expect(try await row(harness, photo) == nil)
        #expect(!FileManager.default.fileExists(atPath: harness.files.directory(of: photo.id).path))
        #expect(queue.board.media(of: harness.activityID, merging: []).isEmpty)
    }

    // MARK: - Relaunch

    @Test func anUploadingRowReadAtRelaunchResumesItsUpload() async throws {
        let harness = try MediaUploadHarness()
        MediaUploadHarness.route { _ in MediaUploadHarness.uploadURLs() }
        let (_, photo) = try await sendingPhoto(harness, transfer: FakeMediaTransfer())
        // Killed: the session's tasks are gone with the app.
        let relaunched = FakeMediaTransfer()

        await harness.makeQueue(transfer: relaunched).resume()

        #expect(harness.requestLines == ["POST upload-urls", "POST upload-urls"])
        #expect(relaunched.startedNames == ["original.jpg", "thumb.jpg"])
        #expect(try await row(harness, photo)?.state == .uploading)
    }

    @Test func filesStillRunningInTheSessionAreNotSentTwiceAtRelaunch() async throws {
        let harness = try MediaUploadHarness()
        MediaUploadHarness.route { _ in MediaUploadHarness.uploadURLs() }
        let first = FakeMediaTransfer()
        let (_, photo) = try await sendingPhoto(harness, transfer: first)
        let relaunched = FakeMediaTransfer(active: Set(first.started.map(\.key)))

        let queue = harness.makeQueue(transfer: relaunched)
        await queue.resume()
        await finishAll(queue, first)

        #expect(relaunched.started.isEmpty)
        #expect(harness.requestLines == ["POST upload-urls", "POST media"])
        _ = photo
    }

    @Test func anExportCutByTheAppBeingKilledIsDroppedAtRelaunch() async throws {
        let harness = try MediaUploadHarness()
        let lost = MediaUpload(
            mediaID: UUID(), activityID: harness.activityID, kind: .photo, position: 0, state: .exporting,
            failure: nil, files: [], attempts: 0, nextAttemptAt: MediaUploadHarness.now, createdAt: MediaUploadHarness.now
        )
        try await harness.store.insert([lost])
        _ = try harness.files.makeDirectory(of: lost.mediaID)

        await harness.makeQueue(transfer: FakeMediaTransfer()).resume()

        #expect(try await harness.store.all().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: harness.files.directory(of: lost.mediaID).path))
        #expect(harness.analytics.names.isEmpty)
    }

    // MARK: - The author's carousel

    @Test func theCarouselShowsTheLocalPhotoWithItsRingThenTheConfirmedOneOnce() async throws {
        let harness = try MediaUploadHarness()
        let photoID = Locked<UUID?>(nil)
        MediaUploadHarness.route { step in
            step == "upload-urls" ? MediaUploadHarness.uploadURLs() : MediaUploadHarness.confirmed(photoID.value!)
        }
        let transfer = FakeMediaTransfer()
        let (queue, photo) = try await sendingPhoto(harness, transfer: transfer, position: 1)
        photoID.value = photo.id
        let existing = ActivityMedia(
            id: UUID(), kind: .photo, width: 2_048, height: 1_536, duration: nil,
            url: URL(string: "https://bucket.test/a.jpg")!, posterURL: nil, thumbURL: URL(string: "https://bucket.test/a-thumb.jpg")!
        )
        let original = try #require(transfer.started.first { $0.key.name == "original.jpg" })
        await queue.handle(.progress(original.key, sent: Int64(original.contentLength), total: Int64(original.contentLength)))

        let sending = queue.board.media(of: harness.activityID, merging: [existing])
        #expect(sending.map(\.id) == [existing.id, photo.id])
        guard case .sending(let progress) = sending[1].upload else {
            Issue.record("no progress ring: \(String(describing: sending[1].upload))")
            return
        }
        #expect(progress > 0.5 && progress < 1)
        #expect(sending[1].url.isFileURL && sending[1].thumbURL.isFileURL)

        await finishAll(queue, transfer)
        let confirmed = try #require(queue.board.media(of: harness.activityID, merging: [existing]).last)
        // The screen reloads: the API now returns it too.
        let reloaded = queue.board.media(of: harness.activityID, merging: [existing, confirmed])

        #expect(confirmed.id == photo.id && confirmed.upload == nil)
        #expect(reloaded.map(\.id) == [existing.id, photo.id])
    }
}
