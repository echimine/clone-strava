import Foundation
import Testing
@testable import StravaClone

/// Nested in `ActivitySenderTests` to share its serialized network stub.
extension ActivitySenderTests {
    /// The finish screen's Media wait for their Activity (ADR-037 §6): none goes before
    /// `create_activity` succeeds; then the coordinator wakes them, and they go in parallel with
    /// `upload_trace` and `complete_activity`, which do not wait for them. Real sender over the
    /// stubbed API, real Media queue on the same GRDB database, fake background session.
    @MainActor
    struct RecordingMediaSendTests {
        private let harness: ActivitySenderHarness
        private let media: MediaUploadHarness
        private let server = FakeMediaUploadServer()
        private let transfer = FakeMediaTransfer()

        init() throws {
            ActivitySenderHarness.resetNetwork()
            harness = try ActivitySenderHarness()
            media = try MediaUploadHarness(database: harness.database)
        }

        /// A photo exported on the finish screen: its row as Save writes it.
        private func exportedPhoto(position: Int = 0) -> MediaUpload {
            MediaUpload(
                mediaID: UUID(),
                activityID: harness.id,
                kind: .photo,
                position: position,
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

        private func makeCoordinator(_ sender: ActivitySender, _ queue: MediaUploadQueue) -> SyncQueueCoordinator {
            SyncQueueCoordinator(
                activitySender: sender,
                localActivities: harness.store,
                itineraryChanges: QueuedSender(send: {}),
                mediaUploads: QueuedSender(
                    send: { await queue.send(ignoringBackoff: true) },
                    activityCreated: { _ in await queue.send() }
                ),
                reloadFeed: { true },
                backgroundTasks: RecordingBackgroundTasks()
            )
        }

        private func makeQueue() -> MediaUploadQueue {
            let store = harness.store
            return media.makeQueue(transfer: transfer, server: server, canSend: { await store.isKnownToServer($0) })
        }

        @Test func noMediaGoesWhileTheActivityIsNotCreated() async throws {
            let photo = exportedPhoto()
            try await harness.saveRecordedActivity(media: [photo])
            ActivitySenderHarness.route { _ in .offline }
            let queue = makeQueue()
            let coordinator = makeCoordinator(harness.makeSender(), queue)

            await coordinator.activitySaved()
            await coordinator.appBecameActive()
            await queue.send(ignoringBackoff: true)

            #expect(harness.requestLines.allSatisfy { $0 == "POST /v1/activities" })
            #expect(server.calls.isEmpty)
            #expect(transfer.started.isEmpty)
            #expect(try await media.store.upload(photo.mediaID)?.state == .uploading)
        }

        @Test func atCreatedTheMediaGoWithoutWaitingForTheTraceOrTheCompletion() async throws {
            let photo = exportedPhoto()
            try await harness.saveRecordedActivity(media: [photo])
            let harness = harness
            ActivitySenderHarness.route { step in
                switch step {
                case "create": harness.created()
                // The trace's `PUT` never answers: the chain stays at `upload_trace`.
                case "upload": .hang
                default: harness.completed()
                }
            }
            let queue = makeQueue()
            let sender = harness.makeSender()
            let coordinator = makeCoordinator(sender, queue)

            let saved = Task { await coordinator.activitySaved() }
            defer {
                sender.cancelPass()
                saved.cancel()
            }

            #expect(await eventually { transfer.started.count == 2 })
            #expect(server.calls == ["upload-urls \(photo.mediaID)"])
            #expect(transfer.startedNames == ["original.jpg", "thumb.jpg"])
            #expect(!harness.requestLines.contains { $0.hasSuffix("/complete") })
            #expect(try await harness.store.activity(harness.id)?.state == .created)
        }

        @Test func theCreationSendsMediaFirst() async throws {
            try await harness.saveRecordedActivity(mediaFirst: true, media: [exportedPhoto()])
            ActivitySenderHarness.route { _ in .offline }

            await harness.makeSender().send()

            let body = try #require(harness.requests.first?.httpBody)
            let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(json["mediaFirst"] as? Bool == true)
        }

        @Test func anActivityFailedByTheWorkerStillSendsItsMedia() async throws {
            let photo = exportedPhoto()
            try await harness.saveRecordedActivity(media: [photo])
            try await harness.store.markFailed(harness.id, reason: "invalid_trace")

            await makeQueue().send(ignoringBackoff: true)

            #expect(server.calls == ["upload-urls \(photo.mediaID)"])
            #expect(transfer.started.count == 2)
        }

        @Test func anActivityTheAPIRefusedToCreateKeepsItsMedia() async throws {
            let photo = exportedPhoto()
            try await harness.saveRecordedActivity(media: [photo])
            let creation = try #require(try await harness.store.operation(for: harness.id))
            try await harness.store.fail(creation, reason: "validation_error")

            await makeQueue().send(ignoringBackoff: true)

            #expect(server.calls.isEmpty)
            #expect(transfer.started.isEmpty)
        }
    }
}
