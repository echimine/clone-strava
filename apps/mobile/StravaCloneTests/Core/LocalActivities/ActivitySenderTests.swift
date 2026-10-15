import Foundation
import Testing
@testable import StravaClone

/// A saved Activity's journey to the server (ADR-031 §14): the real API adapter over a
/// stubbed network, the real GRDB store in memory, one test per line of the response table.
@MainActor
@Suite(.serialized)
struct ActivitySenderTests {
    init() {
        ActivitySenderHarness.resetNetwork()
    }

    private func state(_ harness: ActivitySenderHarness) async throws -> LocalActivityState? {
        try await harness.store.activity(harness.id)?.state
    }

    private func pendingStep(_ harness: ActivitySenderHarness) async throws -> ActivityOperationStep? {
        try await harness.store.operation(for: harness.id)?.step
    }

    // MARK: - The chain

    @Test func createUploadThenCompleteTakeTheActivityToProcessing() async throws {
        let harness = try ActivitySenderHarness()
        try await harness.saveRecordedActivity()
        ActivitySenderHarness.route { step in
            switch step {
            case "create": harness.created()
            case "upload": .status(200)
            default: harness.completed()
            }
        }

        await harness.makeSender().send()

        #expect(harness.requestLines == ["POST /v1/activities", "PUT bucket", "POST /v1/activities/\(harness.id)/complete"])
        #expect(try await state(harness) == .processing)
        #expect(try await pendingStep(harness) == nil)
    }

    @Test func theCreationSendsTheProvisionalValuesWithoutElevationGain() async throws {
        let harness = try ActivitySenderHarness()
        try await harness.saveRecordedActivity()
        ActivitySenderHarness.route { _ in .offline }

        await harness.makeSender().send()

        let body = try #require(harness.requests.first?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["id"] as? String == harness.id.description)
        #expect(json["sportTypeCode"] as? String == "run")
        #expect(json["title"] as? String == "Course à pied le matin")
        #expect(json["visibility"] as? String == "followers")
        #expect(json["isManual"] as? Bool == false)
        #expect(json["distanceM"] as? Double == 1_500)
        #expect(json["movingTimeS"] as? Int == 540)
        #expect(json["elapsedTimeS"] as? Int == 600)
        #expect(json["elevationGainM"] == nil)
        #expect(json["startedAt"] as? String == "2026-10-15T07:00:00Z")
        #expect(json["endedAt"] as? String == "2026-10-15T07:10:00Z")
    }

    @Test func theTraceIsAGzippedV2BuiltFromThePointsAndPauses() async throws {
        let harness = try ActivitySenderHarness()
        try await harness.saveRecordedActivity()
        ActivitySenderHarness.route { step in step == "create" ? harness.created() : .offline }

        await harness.makeSender().send()

        let upload = try #require(harness.requests.last)
        #expect(upload.httpMethod == "PUT")
        #expect(upload.value(forHTTPHeaderField: "Content-Type") == "application/gzip")
        #expect(upload.value(forHTTPHeaderField: "Authorization") == nil)
        let gzip = try #require(upload.httpBody)
        let json = try (Data(gzip.dropFirst(10).dropLast(8)) as NSData).decompressed(using: .zlib) as Data
        let trace = try JSONDecoder().decode(TraceFile.Trace.self, from: json)
        let start = ActivitySenderHarness.start.epochMilliseconds
        #expect(trace.schemaVersion == 2)
        #expect(trace.points.map(\.timestampMs) == [start, start + 60_000, start + 600_000])
        // The finished Pause is sent, the final one (the end of the Activity) is not.
        #expect(trace.pauses == [TraceFile.Pause(startMs: start + 60_000, endMs: start + 120_000)])
    }

    // MARK: - Temporary failures

    @Test func offlineAtSaveTheActivityLeavesWhenTheNetworkIsBack() async throws {
        let harness = try ActivitySenderHarness()
        try await harness.saveRecordedActivity()
        let online = Locked(false)
        ActivitySenderHarness.route { step in
            guard online.value else { return .offline }
            switch step {
            case "create": return harness.created()
            case "upload": return .status(200)
            default: return harness.completed()
            }
        }
        let sender = harness.makeSender()

        await sender.send()
        #expect(try await state(harness) == .recorded)
        #expect(try await harness.store.operation(for: harness.id)?.attempts == 1)

        online.value = true
        await sender.send(ignoringBackoff: true)
        #expect(try await state(harness) == .processing)
    }

    @Test func aServerErrorIsTriedAgainFrom2To300SecondsWithoutLimit() async throws {
        let harness = try ActivitySenderHarness()
        try await harness.saveRecordedActivity()
        ActivitySenderHarness.route { _ in .status(503) }
        let sender = harness.makeSender()

        await sender.send()
        #expect(try await harness.store.operation(for: harness.id)?.nextAttemptAt == ActivitySenderHarness.now.addingTimeInterval(2))
        for _ in 0 ..< 11 {
            await sender.send(ignoringBackoff: true)
        }

        let operation = try #require(try await harness.store.operation(for: harness.id))
        #expect(operation.step == .create)
        #expect(operation.attempts == 12)
        #expect(operation.nextAttemptAt == ActivitySenderHarness.now.addingTimeInterval(300))
        #expect(try await state(harness) == .recorded)
    }

    @Test func aRefusedSessionIsRefreshedThenTheStepIsSentAgain() async throws {
        let harness = try ActivitySenderHarness()
        try await harness.saveRecordedActivity()
        let creations = Locked(0)
        ActivitySenderHarness.route { step in
            switch step {
            case "create":
                creations.value += 1
                return creations.value == 1 ? .status(401) : harness.created()
            case "upload": return .status(200)
            default: return harness.completed()
            }
        }

        await harness.makeSender().send()

        #expect(harness.refresher.calls == 1)
        #expect(try await state(harness) == .processing)
    }

    // MARK: - Background time taken back

    @Test func cancellingThePassAlsoCancelsTheScheduledRetry() async throws {
        let harness = try ActivitySenderHarness()
        try await harness.saveRecordedActivity()
        ActivitySenderHarness.route { _ in .offline }
        let sleeper = ManualSleeper()
        let sender = harness.makeSender(sleep: sleeper.sleep)
        await sender.send()
        #expect(await eventually { sleeper.waiting == 1 })

        sender.cancelPass()

        #expect(sleeper.waiting == 0)
    }

    @Test func aCancelledPassSchedulesNoRetry() async throws {
        let harness = try ActivitySenderHarness()
        try await harness.saveRecordedActivity()
        ActivitySenderHarness.route { step in step == "create" ? harness.created() : .hang }
        let sleeper = ManualSleeper()
        let sender = harness.makeSender(sleep: sleeper.sleep)
        let sending = Task { await sender.send() }
        #expect(await eventually { harness.requestLines.contains("PUT bucket") })

        sender.cancelPass()
        await sending.value
        // A wake-up Task would be asking for its delay by now.
        try await Task.sleep(for: .milliseconds(300))

        #expect(sleeper.requested.isEmpty)
        #expect(try await pendingStep(harness) == .upload)
    }

    // MARK: - The response table

    @Test func anExpiredUploadURLIsRenewedThenTheTraceIsSentAgain() async throws {
        let harness = try ActivitySenderHarness()
        try await harness.saveRecordedActivity()
        let uploads = Locked(0)
        ActivitySenderHarness.route { step in
            switch step {
            case "create": return harness.created()
            case "upload-url": return harness.renewed()
            case "upload":
                uploads.value += 1
                return uploads.value == 1 ? .status(403) : .status(200)
            default: return harness.completed()
            }
        }

        await harness.makeSender().send()

        #expect(harness.requestLines == [
            "POST /v1/activities",
            "PUT bucket",
            "POST /v1/activities/\(harness.id)/upload-url",
            "PUT bucket",
            "POST /v1/activities/\(harness.id)/complete",
        ])
        #expect(harness.requests[3].url?.query == "sig=renewed")
        #expect(try await state(harness) == .processing)
    }

    @Test func aCreationAnsweredWithoutURLGoesStraightToProcessing() async throws {
        let harness = try ActivitySenderHarness()
        try await harness.saveRecordedActivity()
        ActivitySenderHarness.route { _ in .status(200, #"{"activity":\#(harness.summary("processing"))}"#) }

        await harness.makeSender().send()

        #expect(harness.requestLines == ["POST /v1/activities"])
        #expect(try await state(harness) == .processing)
        #expect(try await pendingStep(harness) == nil)
    }

    @Test func anActivityNoLongerPendingOnUploadURLGoesToComplete() async throws {
        let harness = try ActivitySenderHarness()
        try await harness.saveRecordedActivity()
        ActivitySenderHarness.route { step in
            switch step {
            // A URL already expired: renewed before the upload.
            case "create": harness.created(expiresAt: ActivitySenderHarness.now.addingTimeInterval(-60))
            case "upload-url": ActivitySenderHarness.refused(409, "not_pending")
            default: harness.completed()
            }
        }

        await harness.makeSender().send()

        #expect(harness.requestLines == [
            "POST /v1/activities",
            "POST /v1/activities/\(harness.id)/upload-url",
            "POST /v1/activities/\(harness.id)/complete",
        ])
        #expect(try await state(harness) == .processing)
    }

    @Test func aMissingTraceOnCompleteIsUploadedAgainWithANewURL() async throws {
        let harness = try ActivitySenderHarness()
        try await harness.saveRecordedActivity()
        let completions = Locked(0)
        ActivitySenderHarness.route { step in
            switch step {
            case "create": return harness.created()
            case "upload-url": return harness.renewed()
            case "upload": return .status(200)
            default:
                completions.value += 1
                return completions.value == 1 ? ActivitySenderHarness.refused(409, "trace_missing") : harness.completed()
            }
        }

        await harness.makeSender().send()

        #expect(harness.requestLines == [
            "POST /v1/activities",
            "PUT bucket",
            "POST /v1/activities/\(harness.id)/complete",
            "POST /v1/activities/\(harness.id)/upload-url",
            "PUT bucket",
            "POST /v1/activities/\(harness.id)/complete",
        ])
        #expect(try await state(harness) == .processing)
    }

    @Test(arguments: [
        ("create", 422, "validation_error", LocalActivityState.recorded),
        ("create", 409, "id_conflict", .recorded),
        ("complete", 409, "trace_too_large", .traceUploaded),
        ("complete", 409, "activity_failed", .traceUploaded),
    ])
    func aDefinitiveRefusalFailsTheActivityAndKeepsItsPoints(
        refusedStep: String,
        status: Int,
        code: String,
        resumeState: LocalActivityState
    ) async throws {
        let harness = try ActivitySenderHarness()
        try await harness.saveRecordedActivity()
        ActivitySenderHarness.route { step in
            if step == refusedStep { return ActivitySenderHarness.refused(status, code) }
            return step == "create" ? harness.created() : .status(200)
        }

        await harness.makeSender().send()

        let activity = try #require(try await harness.store.activity(harness.id))
        #expect(activity.state == .failed)
        #expect(activity.failure == LocalActivityFailure(reason: code, resumeState: resumeState))
        #expect(try await pendingStep(harness) == nil)
        #expect(try await harness.store.trace(of: harness.id).points.count == 3)
    }

    // MARK: - Resume

    @Test func anAppKilledAfterTheCreationResumesAtTheUpload() async throws {
        let harness = try ActivitySenderHarness()
        try await harness.saveRecordedActivity()
        ActivitySenderHarness.route { step in step == "create" ? harness.created() : .offline }
        await harness.makeSender().send()
        #expect(try await state(harness) == .created)

        // Relaunch: a new sender over the same database.
        ActivitySenderHarness.resetNetwork()
        ActivitySenderHarness.route { step in step == "upload" ? .status(200) : harness.completed() }
        await harness.makeSender().send(ignoringBackoff: true)

        #expect(harness.requestLines == ["PUT bucket", "POST /v1/activities/\(harness.id)/complete"])
        #expect(try await state(harness) == .processing)
    }

    @Test func anAppKilledAfterTheUploadResumesAtComplete() async throws {
        let harness = try ActivitySenderHarness()
        try await harness.saveRecordedActivity()
        ActivitySenderHarness.route { step in
            switch step {
            case "create": harness.created()
            case "upload": .status(200)
            default: .offline
            }
        }
        await harness.makeSender().send()
        #expect(try await state(harness) == .traceUploaded)

        ActivitySenderHarness.resetNetwork()
        ActivitySenderHarness.route { _ in harness.completed() }
        await harness.makeSender().send(ignoringBackoff: true)

        #expect(harness.requestLines == ["POST /v1/activities/\(harness.id)/complete"])
        #expect(try await state(harness) == .processing)
    }

    // MARK: - Tracking

    private func processingActivity() async throws -> ActivitySenderHarness {
        let harness = try ActivitySenderHarness()
        try await harness.saveRecordedActivity()
        ActivitySenderHarness.route { _ in .status(200, #"{"activity":\#(harness.summary("processing"))}"#) }
        await harness.makeSender().send()
        ActivitySenderHarness.resetNetwork()
        return harness
    }

    @Test func aProcessedActivityIsReportedThenWiped() async throws {
        let harness = try await processingActivity()
        ActivitySenderHarness.route { _ in harness.detail("processed") }
        let sender = harness.makeSender()

        let processed = await sender.trackProcessing()
        #expect(processed == [harness.id])
        #expect(harness.requestLines == ["GET /v1/activities/\(harness.id)"])

        try await harness.store.wipe(processed)
        #expect(try await harness.store.activity(harness.id) == nil)
        #expect(try await harness.store.trace(of: harness.id).points.isEmpty)
    }

    @Test func anActivityStillProcessingStaysAsItIs() async throws {
        let harness = try await processingActivity()
        ActivitySenderHarness.route { _ in harness.detail("processing") }

        #expect(await harness.makeSender().trackProcessing().isEmpty)
        #expect(try await state(harness) == .processing)
    }

    @Test func aWorkerFailureFailsTheActivityAndKeepsItsPoints() async throws {
        let harness = try await processingActivity()
        ActivitySenderHarness.route { _ in harness.detail("failed", error: "invalid_trace") }

        #expect(await harness.makeSender().trackProcessing().isEmpty)

        let activity = try #require(try await harness.store.activity(harness.id))
        #expect(activity.state == .failed)
        #expect(activity.failure?.reason == "invalid_trace")
        #expect(try await harness.store.trace(of: harness.id).points.count == 3)
    }
}
