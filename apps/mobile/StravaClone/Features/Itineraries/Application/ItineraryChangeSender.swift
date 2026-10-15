import Foundation

/// Drains the `sync_operation` queue of Itinerary changes (ADR-008 §3, ADR-030 §8). A rename or
/// a delete is recorded first, so it shows at once, offline too; then it is sent:
/// - right after the action, when the network comes back and when the app returns to the
///   foreground (through `ItinerarySynchronizer.refresh`), with no `BGTaskScheduler`;
/// - no network, timeout or `5xx`: tried again after a capped exponential backoff;
/// - `401`: the session is refreshed, then the change is sent again once;
/// - `404`: a delete counts as done, a rename is dropped and the Itinerary forgotten;
/// - any other client error: the change is dropped and `refusals()` reports it (toast), the
///   server's value shows again.
@MainActor
final class ItineraryChangeSender {
    private let repository: any ItineraryRepository
    private let cache: any ItineraryCache
    private let queue: any ItineraryChangeQueue
    private let sessionRefresher: any SessionRefreshing
    private let backoff: RetryBackoff
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void

    private var sending: Task<Void, Never>?
    /// A trigger arrived during a pass: one more pass runs before `send` returns.
    private var rerun = false
    private var rerunIgnoringBackoff = false
    /// Sends again when the earliest postponed change is due, while the app runs.
    private var wakeUp: Task<Void, Never>?
    /// Bumped by sign-out: a pass started before must not write anything.
    private var generation = 0
    private var refusalContinuations: [UUID: AsyncStream<ItineraryChangeRefusal>.Continuation] = [:]

    init(
        repository: any ItineraryRepository,
        cache: any ItineraryCache,
        queue: any ItineraryChangeQueue,
        sessionRefresher: any SessionRefreshing,
        backoff: RetryBackoff = RetryBackoff(initialDelay: .seconds(2), maxDelay: .seconds(300)),
        now: @escaping @Sendable () -> Date = Date.init,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.repository = repository
        self.cache = cache
        self.queue = queue
        self.sessionRefresher = sessionRefresher
        self.backoff = backoff
        self.now = now
        self.sleep = sleep
    }

    /// Renames locally at once, then sends. The name is trimmed and must have 1 to 100 characters.
    func rename(id: ItineraryID, to name: String) async throws(ItinerarySaveIssue) {
        guard let name = ItineraryName.validated(name) else { throw .invalidName }
        await record(.rename(name: name), for: id)
    }

    /// Hides the Itinerary at once, then sends.
    func delete(id: ItineraryID) async {
        await record(.delete, for: id)
    }

    /// Sends the changes that are due, or every pending one when `ignoringBackoff` (the network
    /// is back, the app is in the foreground again). Joins the pass already running.
    func send(ignoringBackoff: Bool = false) async {
        if let sending {
            rerun = true
            rerunIgnoringBackoff = rerunIgnoringBackoff || ignoringBackoff
            await sending.value
            return
        }
        let generation = generation
        let task = Task { await self.run(ignoringBackoff: ignoringBackoff, generation: generation) }
        sending = task
        await task.value
    }

    /// iOS takes the background time back (ADR-031 §14): the pass in flight stops; its request
    /// fails like a lost network, the change stays queued. The scheduled retry is cancelled
    /// too and none is scheduled: the next trigger sends.
    func cancelPass() {
        wakeUp?.cancel()
        wakeUp = nil
        sending?.cancel()
    }

    /// The changes that a sign-out would lose.
    func pendingCount() async -> Int {
        (try? await queue.pending().count) ?? 0
    }

    /// Changes the server turned down, as they happen.
    func refusals() -> AsyncStream<ItineraryChangeRefusal> {
        let (stream, continuation) = AsyncStream.makeStream(of: ItineraryChangeRefusal.self)
        let key = UUID()
        refusalContinuations[key] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.refusalContinuations[key] = nil }
        }
        return stream
    }

    /// Sign-out: forgets every pending change; a pass in flight writes nothing more.
    func clear() async {
        generation += 1
        wakeUp?.cancel()
        wakeUp = nil
        sending?.cancel()
        sending = nil
        rerun = false
        rerunIgnoringBackoff = false
        try? await queue.clear()
    }

    private func record(_ change: ItineraryChange, for id: ItineraryID) async {
        do {
            try await queue.enqueue(change, for: id, at: now())
        } catch {
            return
        }
        await send()
    }

    private func run(ignoringBackoff: Bool, generation: Int) async {
        var ignoringBackoff = ignoringBackoff
        repeat {
            rerun = false
            await sendPending(ignoringBackoff: ignoringBackoff, generation: generation)
            ignoringBackoff = rerunIgnoringBackoff
            rerunIgnoringBackoff = false
        } while rerun && self.generation == generation
        guard self.generation == generation else { return }
        sending = nil
        guard !Task.isCancelled else { return }
        await scheduleWakeUp(generation: generation)
    }

    /// Oldest first: at most one change per Itinerary is pending (coalesced by the queue).
    private func sendPending(ignoringBackoff: Bool, generation: Int) async {
        guard let pending = try? await queue.pending() else { return }
        let date = now()
        for change in pending where ignoringBackoff || SyncQueueSchedule.isDue(change.nextAttemptAt, at: date) {
            guard self.generation == generation, !Task.isCancelled else { return }
            await send(change, generation: generation)
        }
    }

    private func send(_ pending: PendingItineraryChange, generation: Int) async {
        let result = await attempt(pending.change, on: pending.itineraryID)
        guard self.generation == generation else { return }
        switch result {
        case .success(let renamed?):
            // The server's name first, then the change: the local name never flickers.
            try? await cache.store(renamed)
            try? await queue.remove(pending)
        case .success(nil), .failure(.notFound):
            try? await cache.delete(id: pending.itineraryID)
        case .failure(let error) where error.isRetryable || error == .unauthorized:
            let delay = backoff.delay(beforeRetry: pending.attempts)
            try? await queue.postpone(pending, until: now().addingTimeInterval(delay.timeInterval), error: "\(error)")
        case .failure:
            try? await queue.remove(pending)
            let refusal: ItineraryChangeRefusal = pending.change == .delete ? .delete : .rename
            for continuation in refusalContinuations.values {
                continuation.yield(refusal)
            }
        }
    }

    /// The request, sent once more after a `401` if the session could be refreshed.
    private func attempt(_ change: ItineraryChange, on id: ItineraryID) async -> Result<ItineraryDetail?, ItineraryError> {
        let result = await request(change, on: id)
        guard case .failure(.unauthorized) = result, await sessionRefresher.refresh() else { return result }
        return await request(change, on: id)
    }

    /// The renamed Itinerary, or nil once deleted.
    private func request(_ change: ItineraryChange, on id: ItineraryID) async -> Result<ItineraryDetail?, ItineraryError> {
        do throws(ItineraryError) {
            switch change {
            case .rename(let name):
                return .success(try await repository.rename(id: id, to: name))
            case .delete:
                try await repository.delete(id: id)
                return .success(nil)
            }
        } catch {
            return .failure(error)
        }
    }

    private func scheduleWakeUp(generation: Int) async {
        wakeUp?.cancel()
        wakeUp = nil
        guard let next = try? await queue.pending().map(\.nextAttemptAt).min(), self.generation == generation else {
            return
        }
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
