import Foundation
import Testing
@testable import StravaClone

/// Nested in `ActivitySenderTests` to share its serialized network stub.
extension ActivitySenderTests {
    /// The Media not yet sent follow their Activity (ADR-037 §6, #186): deleted with it, held
    /// while its `delete_activity` waits, back on `409`, gone at sign-out. Real sender over the
    /// stubbed API, real Media queue on the same GRDB database and real files, fake background
    /// session; the coordinator wired as the app wires it (`Di.mediaUploadSender`).
    @MainActor
    struct ActivityDeletionMediaTests {
        private let harness: ActivitySenderHarness
        private let media: MediaUploadHarness
        private let server = FakeMediaUploadServer()
        private let transfer = FakeMediaTransfer()

        init() throws {
            ActivitySenderHarness.resetNetwork()
            harness = try ActivitySenderHarness()
            media = try MediaUploadHarness(database: harness.database)
        }

        /// A photo exported on the finish screen of `activity`: its row as Save writes it, and its
        /// files on disk.
        private func exportedPhoto(of activity: ActivitySenderHarness? = nil) throws -> MediaUpload {
            let id = UUID()
            let directory = try media.files.makeDirectory(of: id)
            for name in [MediaUploadFile.originalPhoto, MediaUploadFile.thumb] {
                try Data([0xFF, 0xD8, 0xFF]).write(to: directory.appendingPathComponent(name))
            }
            return MediaUpload(
                mediaID: id,
                activityID: (activity ?? harness).id,
                kind: .photo,
                position: 0,
                state: .uploading,
                failure: nil,
                width: 1_200,
                height: 900,
                files: [
                    MediaUploadFile(name: MediaUploadFile.originalPhoto, contentType: "image/jpeg", byteCount: 1_000),
                    MediaUploadFile(name: MediaUploadFile.thumb, contentType: "image/jpeg", byteCount: 100),
                ],
                attempts: 0,
                nextAttemptAt: MediaUploadHarness.now,
                createdAt: MediaUploadHarness.now
            )
        }

        private func makeQueue() -> MediaUploadQueue {
            let store = harness.store
            return media.makeQueue(transfer: transfer, server: server, canSend: { await store.canSendMedia(of: $0) })
        }

        private func makeCoordinator(_ sender: ActivitySender, _ queue: MediaUploadQueue) -> SyncQueueCoordinator {
            SyncQueueCoordinator(
                activitySender: sender,
                localActivities: harness.store,
                itineraryChanges: QueuedSender(send: {}),
                mediaUploads: Di.mediaUploadSender(queue: queue, localActivities: harness.store),
                reloadFeed: { true },
                backgroundTasks: RecordingBackgroundTasks()
            )
        }

        private func hasFiles(_ upload: MediaUpload) -> Bool {
            FileManager.default.fileExists(atPath: media.files.directory(of: upload.mediaID).path)
        }

        /// Created on the server, its photo's `PUT`s running; `delete` answers the server delete.
        private func sendingPhoto(
            delete: @escaping @Sendable () -> ActivityURLProtocolStub.Answer
        ) async throws -> (ActivitySender, MediaUploadQueue, SyncQueueCoordinator, MediaUpload) {
            let photo = try exportedPhoto()
            try await harness.saveRecordedActivity(media: [photo])
            let harness = harness
            ActivitySenderHarness.route { step in
                switch step {
                case "create": harness.created()
                case "delete": delete()
                default: .offline
                }
            }
            let queue = makeQueue()
            let sender = harness.makeSender()
            let coordinator = makeCoordinator(sender, queue)
            await sender.send()
            #expect(await eventually { transfer.started.count == 2 })
            return (sender, queue, coordinator, photo)
        }

        // MARK: - Delete

        @Test func deletedBeforeItsCreationTheActivityTakesItsMediaWithItAtOnce() async throws {
            let photo = try exportedPhoto()
            try await harness.saveRecordedActivity(media: [photo])
            ActivitySenderHarness.route { _ in .offline }
            let queue = makeQueue()
            let sender = harness.makeSender()
            let coordinator = makeCoordinator(sender, queue)

            try await sender.delete(harness.id)

            #expect(harness.requestLines.isEmpty)
            #expect(try await media.store.upload(photo.mediaID) == nil)
            #expect(!hasFiles(photo))
            #expect(transfer.cancelled == [photo.mediaID])
            await queue.send(ignoringBackoff: true)
            #expect(server.calls.isEmpty)
            _ = coordinator
        }

        @Test func whileTheServerDeleteWaitsTheMediaAreHeldThenGoWithIt204() async throws {
            try await theMediaGoOnceTheServerHasDeleted(answer: .status(204))
        }

        @Test func whileTheServerDeleteWaitsTheMediaAreHeldThenGoWithIt404() async throws {
            try await theMediaGoOnceTheServerHasDeleted(answer: ActivitySenderHarness.refused(404, "not_found"))
        }

        private func theMediaGoOnceTheServerHasDeleted(answer: ActivityURLProtocolStub.Answer) async throws {
            let online = Locked(false)
            let (sender, queue, coordinator, photo) = try await sendingPhoto { online.value ? answer : .offline }
            defer { _ = coordinator }

            // Offline: the uploads stop, the row and files wait for the server's answer.
            try await sender.delete(harness.id)
            #expect(transfer.cancelled == [photo.mediaID])
            #expect(await transfer.activeFiles().isEmpty)
            #expect(try await media.store.upload(photo.mediaID) != nil)
            #expect(hasFiles(photo))
            await queue.send(ignoringBackoff: true)
            #expect(server.calls == ["upload-urls \(photo.mediaID)"])
            #expect(transfer.started.count == 2)

            online.value = true
            await sender.send(ignoringBackoff: true)

            #expect(try await harness.store.activity(harness.id) == nil)
            #expect(try await media.store.upload(photo.mediaID) == nil)
            #expect(!hasFiles(photo))
            #expect(queue.board.media(of: harness.id, merging: []).isEmpty)
        }

        @Test func aDeleteRefusedByTheServerSendsTheMediaAgain() async throws {
            let (sender, _, coordinator, photo) = try await sendingPhoto { ActivitySenderHarness.refused(409, "not_deletable") }
            defer { _ = coordinator }

            try await sender.delete(harness.id)

            #expect(try await harness.store.activity(harness.id)?.state == .processing)
            #expect(await eventually { transfer.started.count == 4 })
            #expect(server.calls == ["upload-urls \(photo.mediaID)", "upload-urls \(photo.mediaID)"])
            #expect(try await media.store.upload(photo.mediaID)?.state == .uploading)
            #expect(hasFiles(photo))
        }

        // MARK: - Retry

        @Test func refusedAtItsCreationTheMediaWaitThenGoOnceRetryCreatesIt() async throws {
            let photo = try exportedPhoto()
            try await harness.saveRecordedActivity(media: [photo])
            let refused = Locked(true)
            let harness = harness
            ActivitySenderHarness.route { step in
                switch step {
                case "create": refused.value ? ActivitySenderHarness.refused(422, "validation_error") : harness.created()
                default: .offline
                }
            }
            let queue = makeQueue()
            let sender = harness.makeSender()
            let coordinator = makeCoordinator(sender, queue)
            defer { _ = coordinator }
            await sender.send()
            #expect(try await harness.store.activity(harness.id)?.state == .failed)

            await queue.send(ignoringBackoff: true)
            #expect(server.calls.isEmpty)

            refused.value = false
            try await sender.retry(harness.id)

            #expect(await eventually { transfer.started.count == 2 })
            #expect(server.calls == ["upload-urls \(photo.mediaID)"])
        }

        // MARK: - Sign-out

        @Test func signOutCountsTheMediaNotYetSentThenLeavesNoTaskNorFile() async throws {
            let first = try exportedPhoto()
            let second = try exportedPhoto()
            try await harness.saveRecordedActivity(media: [first, second])
            let deleting = try ActivitySenderHarness(database: harness.database)
            let given = try exportedPhoto(of: deleting)
            try await deleting.saveRecordedActivity(media: [given])
            let harness = harness
            ActivitySenderHarness.route { step in
                step == "create" ? harness.created() : .offline
            }
            let queue = makeQueue()
            let sender = harness.makeSender()
            let coordinator = makeCoordinator(sender, queue)
            await sender.send()
            #expect(await eventually { transfer.started.count == 6 })
            // A deleted Activity's Media are already given up.
            try await sender.delete(deleting.id)

            #expect(await coordinator.unsentMediaCount() == 2)

            await coordinator.signOut()

            #expect(await transfer.activeFiles().isEmpty)
            #expect(try await media.store.count() == 0)
            let folders = try FileManager.default.contentsOfDirectory(atPath: media.files.root.path)
            #expect(folders.isEmpty)
            #expect(await coordinator.unsentMediaCount() == 0)
        }

        // MARK: - App killed

        @Test func killedBeforeSaveTheFinishScreensExportsAreDeletedAtRelaunch() async throws {
            let queue = makeQueue()
            let photo = MediaUploadHarness.photo()
            queue.prepare([photo])
            #expect(await eventually { queue.board.preparation(of: photo.id) == .ready })
            #expect(FileManager.default.fileExists(atPath: media.files.directory(of: photo.id).path))

            await makeQueue().resume()

            #expect(!FileManager.default.fileExists(atPath: media.files.directory(of: photo.id).path))
            #expect(try await media.store.count() == 0)
        }
    }
}
