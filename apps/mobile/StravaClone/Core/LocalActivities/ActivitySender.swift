import Foundation

/// Drains the `sync_operation` queue of local Activities (ADR-031 §14), modelled on
/// `ItineraryChangeSender`: `create_activity` → `upload_trace` → `complete_activity`, each
/// success replacing its operation with the next one in the transaction of the state change
/// (`recorded` → `created` → `trace_uploaded` → `processing`). Woken by the queue coordinator
/// in `App/`; a chain left unfinished resumes at its step on the next trigger.
///
/// Response table:
/// - offline, timeout, `5xx`: tried again from 2 s to 300 s, no attempt limit;
/// - `401`: the session is refreshed, then the step is sent again;
/// - `403` from the bucket (URL expired): `upload-url`, then upload again;
/// - `200` without URL on `POST`: straight to `processing`;
/// - `409` on `upload-url` (no longer `pending`): on to `complete`;
/// - `409 trace_missing` on `complete`: back to `upload_trace` with a new URL;
/// - `422`, `409` on `POST`, `409 trace_too_large`, `409 activity_failed`: `failed` with the code.
@MainActor
final class ActivitySender {
    /// An upload URL closer than this to its expiry is renewed before the `PUT`.
    static let uploadURLMargin: TimeInterval = 30
    /// Steps one Activity may take in a pass: guards against a server bouncing between two steps.
    private static let maxStepsPerPass = 8

    private let server: any ActivityServer
    private let store: GRDBLocalActivityStore
    private let sessionRefresher: any SessionRefreshing
    private let backoff: RetryBackoff
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void

    private var sending: Task<Void, Never>?
    private var rerun = false
    private var rerunIgnoringBackoff = false
    private var wakeUp: Task<Void, Never>?

    init(
        server: any ActivityServer,
        store: GRDBLocalActivityStore,
        sessionRefresher: any SessionRefreshing,
        backoff: RetryBackoff = RetryBackoff(initialDelay: .seconds(2), maxDelay: .seconds(300)),
        now: @escaping @Sendable () -> Date = Date.init,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.server = server
        self.store = store
        self.sessionRefresher = sessionRefresher
        self.backoff = backoff
        self.now = now
        self.sleep = sleep
    }

    /// Sends the steps that are due, or every pending one when `ignoringBackoff` (network back,
    /// foreground, pull-to-refresh). Joins the pass already running.
    func send(ignoringBackoff: Bool = false) async {
        if let sending {
            rerun = true
            rerunIgnoringBackoff = rerunIgnoringBackoff || ignoringBackoff
            await sending.value
            return
        }
        let task = Task { await self.run(ignoringBackoff: ignoringBackoff) }
        sending = task
        await task.value
    }

    /// iOS takes the background time back (ADR-031 §14): the pass in flight stops. Its request
    /// fails like a lost network and nothing is written past it, so each operation stays at
    /// its step for the next trigger. The scheduled retry is cancelled too and none is scheduled.
    func cancelPass() {
        wakeUp?.cancel()
        wakeUp = nil
        sending?.cancel()
    }

    /// Follows the Activities in `processing` with `GET /v1/activities/:id` (ADR-031 §14): a
    /// worker failure turns the local Activity `failed` (points kept). Returns the processed
    /// ones: the caller reloads the feed, then `wipe`s them.
    func trackProcessing() async -> [ActivityID] {
        guard let ids = try? await store.activityIDs(in: .processing) else { return [] }
        var processed: [ActivityID] = []
        for id in ids {
            switch await attempt({ () async throws(ActivityServerError) in try await self.server.status(of: id) }) {
            case .success(.processed):
                processed.append(id)
            case .success(.failed(let reason)):
                try? await store.markFailed(id, reason: reason ?? "processing_error")
            case .success, .failure:
                continue
            }
        }
        return processed
    }

    /// Delete (ADR-031 §14): gone from the phone at once; the server copy, if any, is deleted
    /// by a `delete_activity` sent right away. Refused once `processing`.
    func delete(_ id: ActivityID) async throws {
        guard try await store.delete(id) else { return }
        await send()
    }

    /// Retry after an API refusal: resumes at the refused step. Refused otherwise.
    func retry(_ id: ActivityID) async throws {
        try await store.retry(id)
        await send()
    }

    /// The Activities a sign-out would lose (`recorded`, `created`, `trace_uploaded`, `failed`).
    func unsentCount() async -> Int {
        (try? await store.unsentCount()) ?? 0
    }

    /// Sign-out: every local Activity is wiped, nothing more is sent.
    func clear() async {
        wakeUp?.cancel()
        wakeUp = nil
        try? await store.clear()
    }

    /// Processed Activities, once the feed shows them: row, points and Pauses go.
    func wipe(_ ids: [ActivityID]) async {
        try? await store.wipe(ids)
    }

    // MARK: - Passes

    private func run(ignoringBackoff: Bool) async {
        var ignoringBackoff = ignoringBackoff
        repeat {
            rerun = false
            await sendPending(ignoringBackoff: ignoringBackoff)
            ignoringBackoff = rerunIgnoringBackoff
            rerunIgnoringBackoff = false
        } while rerun
        sending = nil
        guard !Task.isCancelled else { return }
        await scheduleWakeUp()
    }

    private func sendPending(ignoringBackoff: Bool) async {
        guard let pending = try? await store.pendingOperations() else { return }
        let date = now()
        for operation in pending where ignoringBackoff || SyncQueueSchedule.isDue(operation.nextAttemptAt, at: date) {
            guard !Task.isCancelled else { return }
            var current: PendingActivityOperation? = operation
            var steps = 0
            while let step = current, steps < Self.maxStepsPerPass {
                current = await perform(step)
                steps += 1
            }
        }
    }

    /// Runs one step; returns the next one when it is due at once.
    private func perform(_ operation: PendingActivityOperation) async -> PendingActivityOperation? {
        switch operation.step {
        case .create: await create(operation)
        case .upload: await upload(operation)
        case .complete: await complete(operation)
        case .delete: await deleteOnServer(operation)
        }
    }

    private func deleteOnServer(_ operation: PendingActivityOperation) async -> PendingActivityOperation? {
        switch await attempt({ () async throws(ActivityServerError) in try await self.server.delete(operation.activityID) }) {
        case .success, .failure(.refused):
            // Deleted, or no longer deletable (`409`: already handed to the worker).
            try? await store.drop(operation)
        case .failure(let error):
            await handle(error, of: operation)
        }
        return nil
    }

    private func create(_ operation: PendingActivityOperation) async -> PendingActivityOperation? {
        guard let activity = try? await store.activity(operation.activityID) else { return nil }
        switch await attempt({ () async throws(ActivityServerError) in try await self.server.create(activity) }) {
        case .success(.awaitingTrace(let target)):
            return try? await store.advance(operation, to: .created, next: .upload, uploadTarget: target, at: now())
        case .success(.alreadyProcessing):
            return try? await store.advance(operation, to: .processing, next: nil, at: now())
        case .failure(let error):
            await handle(error, of: operation)
            return nil
        }
    }

    private func upload(_ operation: PendingActivityOperation) async -> PendingActivityOperation? {
        var target = operation.uploadTarget
        let renewing = target.map { $0.expiresAt <= now().addingTimeInterval(Self.uploadURLMargin) } ?? true
        if renewing {
            switch await attempt({ () async throws(ActivityServerError) in try await self.server.renewUploadURL(for: operation.activityID) }) {
            case .success(let renewed):
                target = renewed
                try? await store.setUploadTarget(renewed, of: operation)
            case .failure(.notPending):
                return try? await store.advance(operation, to: .traceUploaded, next: .complete, at: now())
            case .failure(let error):
                await handle(error, of: operation)
                return nil
            }
        }
        guard let target, let trace = try? await store.trace(of: operation.activityID),
              let data = try? TraceFile.gzippedJSON(points: trace.points, pauses: trace.pauses)
        else { return nil }
        let result = await attempt({ () async throws(ActivityServerError) in try await self.server.uploadTrace(data, to: target) })
        switch result {
        case .success:
            return try? await store.advance(operation, to: .traceUploaded, next: .complete, at: now())
        case .failure(.uploadURLExpired) where !renewing:
            // A URL from `POST`: renewed once, then sent again.
            try? await store.setUploadTarget(nil, of: operation)
            return try? await store.operation(for: operation.activityID)
        case .failure(let error):
            await handle(error, of: operation)
            return nil
        }
    }

    private func complete(_ operation: PendingActivityOperation) async -> PendingActivityOperation? {
        switch await attempt({ () async throws(ActivityServerError) in try await self.server.complete(operation.activityID) }) {
        case .success:
            return try? await store.advance(operation, to: .processing, next: nil, at: now())
        case .failure(.traceMissing):
            return try? await store.advance(operation, to: .created, next: .upload, at: now())
        case .failure(let error):
            await handle(error, of: operation)
            return nil
        }
    }

    /// Temporary failures wait for the backoff; a refusal makes the Activity `failed`.
    private func handle(_ error: ActivityServerError, of operation: PendingActivityOperation) async {
        switch error {
        case .refused(let code):
            try? await store.fail(operation, reason: code)
        case .notPending, .traceMissing:
            try? await store.fail(operation, reason: "\(error)")
        case .offline, .unavailable, .unauthorized, .uploadURLExpired:
            let delay = backoff.delay(beforeRetry: operation.attempts)
            try? await store.postpone(operation, until: now().addingTimeInterval(delay.timeInterval), error: "\(error)")
        }
    }

    /// The request, sent once more after a `401` if the session could be refreshed.
    private func attempt<T>(
        _ request: @escaping () async throws(ActivityServerError) -> T
    ) async -> Result<T, ActivityServerError> {
        let result = await Self.result(of: request)
        guard case .failure(.unauthorized) = result, await sessionRefresher.refresh() else { return result }
        return await Self.result(of: request)
    }

    private static func result<T>(of request: () async throws(ActivityServerError) -> T) async -> Result<T, ActivityServerError> {
        do throws(ActivityServerError) {
            return .success(try await request())
        } catch {
            return .failure(error)
        }
    }

    private func scheduleWakeUp() async {
        wakeUp?.cancel()
        wakeUp = nil
        guard let next = try? await store.pendingOperations().map(\.nextAttemptAt).min() else { return }
        let delay = max(0, next.timeIntervalSince(now()))
        let sleep = sleep
        wakeUp = Task { [weak self] in
            guard (try? await sleep(.seconds(delay))) != nil, !Task.isCancelled else { return }
            await self?.send()
        }
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
