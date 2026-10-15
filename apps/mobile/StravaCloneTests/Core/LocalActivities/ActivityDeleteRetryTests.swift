import Foundation
import Testing
@testable import StravaClone

/// Delete, Retry and the sign-out wipe of a local Activity (ADR-031 §14), in the serialized
/// suite of `ActivitySenderTests` (shared network stub).
extension ActivitySenderTests {
    private func nothingLeft(_ harness: ActivitySenderHarness) async throws {
        #expect(try await harness.store.activity(harness.id) == nil)
        #expect(try await harness.store.operation(for: harness.id) == nil)
        #expect(try await harness.store.pendingOperations().isEmpty)
        #expect(try await harness.store.trace(of: harness.id).points.isEmpty)
        #expect(try await harness.store.trace(of: harness.id).pauses.isEmpty)
    }

    // MARK: - Delete

    @Test func deletedBeforeItsCreationTheActivityGoesLocallyOnly() async throws {
        let harness = try ActivitySenderHarness()
        try await harness.saveRecordedActivity()
        let sender = harness.makeSender()

        try await sender.delete(harness.id)

        #expect(harness.requestLines.isEmpty)
        try await nothingLeft(harness)
    }

    @Test func deletedAfterItsCreationTheServerCopyIsDeletedAndTheQueuedStepsCancelled() async throws {
        let harness = try ActivitySenderHarness()
        try await harness.saveRecordedActivity()
        let online = Locked(false)
        ActivitySenderHarness.route { step in
            switch step {
            case "create": return harness.created()
            case "delete": return online.value ? .status(204) : .offline
            default: return .offline
            }
        }
        let sender = harness.makeSender()
        await sender.send()
        #expect(try await harness.store.operation(for: harness.id)?.step == .upload)
        ActivityURLProtocolStub.requests.value = []

        // Offline: the card goes at once, the server delete waits for the network; the local
        // copy stays until the server confirms, and no longer counts as unsent.
        try await sender.delete(harness.id)
        #expect(try await harness.store.cards().isEmpty)
        #expect(try await harness.store.activity(harness.id) != nil)
        #expect(try await harness.store.operation(for: harness.id)?.step == .delete)
        #expect(try await harness.store.unsentCount() == 0)

        online.value = true
        await sender.send(ignoringBackoff: true)

        // Tried offline, then sent once the network is back; the upload is never sent again.
        #expect(harness.requestLines == [
            "DELETE /v1/activities/\(harness.id)",
            "DELETE /v1/activities/\(harness.id)",
        ])
        try await nothingLeft(harness)
    }

    @Test func aServerCopyAlreadyGoneCountsAsDeleted() async throws {
        let harness = try ActivitySenderHarness()
        try await harness.saveRecordedActivity()
        ActivitySenderHarness.route { step in
            switch step {
            case "create": harness.created()
            case "delete": ActivitySenderHarness.refused(404, "not_found")
            default: .offline
            }
        }
        let sender = harness.makeSender()
        await sender.send()

        try await sender.delete(harness.id)

        try await nothingLeft(harness)
    }

    /// `409`: the server already handed it to the worker. The card comes back in `processing`,
    /// followed like any other, and the athlete is told why.
    @Test func aDeleteRefusedByTheServerBringsTheActivityBackInProcessing() async throws {
        let harness = try ActivitySenderHarness()
        try await harness.saveRecordedActivity()
        ActivitySenderHarness.route { step in
            switch step {
            case "create": harness.created()
            case "delete": ActivitySenderHarness.refused(409, "not_deletable")
            default: .offline
            }
        }
        let sender = harness.makeSender()
        await sender.send()
        let refusals = Locked<[ActivityID]>([])
        let stream = sender.deletionRefusals()
        let listening = Task { for await id in stream { refusals.value.append(id) } }
        defer { listening.cancel() }

        try await sender.delete(harness.id)

        #expect(try await harness.store.activity(harness.id)?.state == .processing)
        #expect(try await harness.store.operation(for: harness.id) == nil)
        #expect(try await harness.store.cards().map(\.status) == [.processing])
        #expect(try await harness.store.trace(of: harness.id).points.count == 3)
        #expect(await eventually { refusals.value == [harness.id] })

        // Followed until processed, then wiped once the feed shows the server's card.
        ActivitySenderHarness.route { _ in harness.detail("processed") }
        #expect(await sender.trackProcessing() == [harness.id])
    }

    @Test func deletedWhileItsCreationIsInFlightTheServerCopyIsDeletedToo() async throws {
        let harness = try ActivitySenderHarness()
        try await harness.saveRecordedActivity()
        ActivitySenderHarness.route { step in
            switch step {
            case "create":
                // The athlete deletes the card while `POST` is on its way.
                let deleted = DispatchSemaphore(value: 0)
                Task {
                    try? await harness.store.delete(harness.id)
                    deleted.signal()
                }
                deleted.wait()
                return harness.created()
            case "delete": return .status(204)
            default: return .status(200)
            }
        }

        await harness.makeSender().send()

        #expect(harness.requestLines == ["POST /v1/activities", "DELETE /v1/activities/\(harness.id)"])
        try await nothingLeft(harness)
    }

    @Test func anActivityInProcessingCannotBeDeleted() async throws {
        let harness = try ActivitySenderHarness()
        try await harness.saveRecordedActivity()
        ActivitySenderHarness.route { _ in .status(200, #"{"activity":\#(harness.summary("processing"))}"#) }
        let sender = harness.makeSender()
        await sender.send()

        await #expect(throws: LocalActivityActionError.notAllowed) { try await sender.delete(harness.id) }
        #expect(try await harness.store.activity(harness.id)?.state == .processing)
    }

    @Test func aFailedActivityRefusedAtItsCreationIsDeletedLocallyOnly() async throws {
        let harness = try ActivitySenderHarness()
        try await harness.saveRecordedActivity()
        ActivitySenderHarness.route { _ in ActivitySenderHarness.refused(422, "validation_error") }
        let sender = harness.makeSender()
        await sender.send()
        ActivitySenderHarness.resetNetwork()

        try await sender.delete(harness.id)

        #expect(harness.requestLines.isEmpty)
        try await nothingLeft(harness)
    }

    // MARK: - Retry

    @Test func retryAfterA422ResumesAtTheRefusedStep() async throws {
        let harness = try ActivitySenderHarness()
        try await harness.saveRecordedActivity()
        let accepted = Locked(false)
        ActivitySenderHarness.route { step in
            switch step {
            case "create": harness.created()
            case "upload": .status(200)
            default: accepted.value ? harness.completed() : ActivitySenderHarness.refused(422, "validation_error")
            }
        }
        let sender = harness.makeSender()
        await sender.send()
        #expect(try await harness.store.activity(harness.id)?.failure?.resumeState == .traceUploaded)
        ActivitySenderHarness.resetNetwork()
        ActivitySenderHarness.route { _ in harness.completed() }

        try await sender.retry(harness.id)

        #expect(harness.requestLines == ["POST /v1/activities/\(harness.id)/complete"])
        let activity = try #require(try await harness.store.activity(harness.id))
        #expect(activity.state == .processing)
        #expect(activity.failure == nil)
    }

    @Test func retryAfterARefusedCreationSendsTheCreationAgain() async throws {
        let harness = try ActivitySenderHarness()
        try await harness.saveRecordedActivity()
        ActivitySenderHarness.route { _ in ActivitySenderHarness.refused(422, "validation_error") }
        let sender = harness.makeSender()
        await sender.send()
        ActivitySenderHarness.resetNetwork()
        ActivitySenderHarness.route { _ in .offline }

        try await sender.retry(harness.id)

        #expect(harness.requestLines == ["POST /v1/activities"])
        #expect(try await harness.store.activity(harness.id)?.state == .recorded)
        #expect(try await harness.store.operation(for: harness.id)?.step == .create)
    }

    @Test func aWorkerFailureCannotBeRetried() async throws {
        let harness = try ActivitySenderHarness()
        try await harness.saveRecordedActivity()
        ActivitySenderHarness.route { _ in .status(200, #"{"activity":\#(harness.summary("processing"))}"#) }
        let sender = harness.makeSender()
        await sender.send()
        ActivitySenderHarness.route { _ in harness.detail("failed", error: "invalid_trace") }
        _ = await sender.trackProcessing()

        await #expect(throws: LocalActivityActionError.notAllowed) { try await sender.retry(harness.id) }
        #expect(try await harness.store.activity(harness.id)?.state == .failed)
    }

    // MARK: - Sign-out

    @Test func signOutCountsTheActivitiesNotYetSentThenWipesThemAll() async throws {
        let waiting = try ActivitySenderHarness()
        try await waiting.saveRecordedActivity()
        let processing = try ActivitySenderHarness(database: waiting.database)
        try await processing.saveRecordedActivity()
        let refused = try ActivitySenderHarness(database: waiting.database)
        try await refused.saveRecordedActivity()
        ActivitySenderHarness.route { step in
            let id = ActivityURLProtocolStub.requests.value.last?.httpBody.flatMap { String(decoding: $0, as: UTF8.self) } ?? ""
            if id.contains(processing.id.description) { return .status(200, #"{"activity":\#(processing.summary("processing"))}"#) }
            if id.contains(refused.id.description) { return ActivitySenderHarness.refused(422, "validation_error") }
            return .offline
        }
        let sender = waiting.makeSender()
        await sender.send()

        #expect(try await waiting.store.unsentCount() == 2)

        await sender.clear()
        for harness in [waiting, processing, refused] {
            try await nothingLeft(harness)
        }
    }
}
