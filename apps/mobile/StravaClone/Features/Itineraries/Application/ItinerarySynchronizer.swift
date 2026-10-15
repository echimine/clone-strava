import Foundation

/// Keeps the cache equal to the athlete's Itineraries on the server (ADR-030 §8): the full
/// list, every page, is read again on each trigger (foreground, Mes Itinéraires opening,
/// pull-to-refresh, network back) and the local rows no longer returned are deleted. Then
/// every detail whose Itinerary changed (or is new) is fetched, so any detail opens offline.
/// Triggers arriving during a resync join it. Each resync first sends the pending changes
/// (`ItineraryChangeSender`, ADR-008 §3), so the queue drains on the same triggers. In
/// between, realtime events reflect what another device saves or deletes (ADR-030 §9).
@MainActor
final class ItinerarySynchronizer {
    private let repository: any ItineraryRepository
    private let cache: any ItineraryCache
    /// Renames and deletes waiting to be sent; nil where a test needs none.
    private let changes: ItineraryChangeSender?
    /// Changes made on another device (ADR-030 §9); nil where a test needs none.
    private let events: (any ItineraryEventSource)?
    private var running: Task<Result<Void, ItineraryError>, Never>?
    /// Bumped by sign-out: a resync started before must not write anything.
    private var generation = 0
    /// Details fetched at the same time after a resync.
    private let maxConcurrentDetailFetches: Int

    init(
        repository: any ItineraryRepository,
        cache: any ItineraryCache,
        changes: ItineraryChangeSender? = nil,
        events: (any ItineraryEventSource)? = nil,
        maxConcurrentDetailFetches: Int = 4
    ) {
        self.repository = repository
        self.cache = cache
        self.changes = changes
        self.events = events
        self.maxConcurrentDetailFetches = maxConcurrentDetailFetches
    }

    /// Full resync, or the one already running. The cache is left untouched on failure.
    func refresh() async throws(ItineraryError) {
        let task = running ?? start()
        try await task.value.get()
    }

    /// Fetches one detail into the cache (detail screen opened before its prefetch). A `404`
    /// means the Itinerary is gone: it is deleted locally, and the error rethrown.
    func loadDetail(id: ItineraryID) async throws(ItineraryError) {
        try await loadDetail(id: id, generation: generation)
    }

    /// Runs for as long as `connectivity` does (`true` when connected): resyncs each time the
    /// network comes back. The first value is the current state, not a change.
    func resyncOnReconnection(_ connectivity: AsyncStream<Bool>) async {
        var wasConnected: Bool?
        for await isConnected in connectivity {
            defer { wasConnected = isConnected }
            guard isConnected, wasConnected == false else { continue }
            try? await refresh()
        }
    }

    /// Runs for as long as the realtime events do (ADR-030 §9), one event after the other,
    /// so a delete always lands after the save that preceded it.
    func applyRemoteChanges() async {
        guard let events else { return }
        for await event in await events.events() {
            await apply(event)
        }
    }

    /// A save no newer than the cached row is an echo (of this device's own write, or of a
    /// resync that already brought it) and is ignored; otherwise the detail is fetched and
    /// written. A delete forgets the Itinerary and its pending changes; an open detail closes.
    /// A failure leaves the cache as it was: the next resync catches up.
    func apply(_ event: ItineraryEvent) async {
        let generation = generation
        switch event {
        case .deleted(let id):
            try? await cache.delete(id: id)
        case .saved(let id, let updatedAt):
            let cachedAt: Date?
            do {
                cachedAt = try await cache.updatedAt(id: id)
            } catch {
                return
            }
            guard let cachedAt else {
                await loadNewItinerary(id: id, generation: generation)
                return
            }
            guard updatedAt > cachedAt else { return }
            try? await loadDetail(id: id, generation: generation)
        }
    }


    /// Renames locally at once, then sends (ADR-030 §8).
    func rename(id: ItineraryID, to name: String) async throws(ItinerarySaveIssue) {
        try await changes?.rename(id: id, to: name)
    }

    /// Hides the Itinerary at once, then sends the delete.
    func delete(id: ItineraryID) async {
        await changes?.delete(id: id)
    }

    /// Sends the queued changes without a resync, whatever their backoff (queue coordinator in
    /// `App/`, ADR-031 §14).
    func sendPendingChanges() async {
        await changes?.send(ignoringBackoff: true)
    }

    /// The changes a sign-out would lose: the confirmation warns about them.
    func pendingChangeCount() async -> Int {
        await changes?.pendingCount() ?? 0
    }

    /// Changes the server turned down, for a toast.
    func changeRefusals() -> AsyncStream<ItineraryChangeRefusal> {
        changes?.refusals() ?? AsyncStream { $0.finish() }
    }

    /// Sign-out: drops the resync in flight, then wipes the queue and the cache.
    func signOut() async {
        generation += 1
        await changes?.clear()
        if let running {
            running.cancel()
            _ = await running.value
            self.running = nil
        }
        try? await cache.clear()
    }

    private func start() -> Task<Result<Void, ItineraryError>, Never> {
        let generation = generation
        let task = Task { [repository, cache] () -> Result<Void, ItineraryError> in
            defer {
                if self.generation == generation {
                    self.running = nil
                }
            }
            // Push before pull: a resync then already reflects what was just sent.
            await self.changes?.send(ignoringBackoff: true)
            var summaries: [ItinerarySummary] = []
            var cursor: String?
            do throws(ItineraryError) {
                repeat {
                    let page = try await repository.page(cursor: cursor)
                    summaries += page.items
                    cursor = page.nextCursor
                } while cursor != nil && !Task.isCancelled
            } catch {
                return .failure(error)
            }
            guard !Task.isCancelled, self.generation == generation else { return .success(()) }
            do {
                try await cache.replaceSummaries(with: summaries)
            } catch {
                return .failure(.server(code: "local_cache"))
            }
            await self.prefetchDetails(generation: generation)
            return .success(())
        }
        running = task
        return task
    }

    /// Details missing or older than their row, a few at a time. A failure leaves the old
    /// detail in place: it is tried again on the next resync.
    private func prefetchDetails(generation: Int) async {
        guard let ids = try? await cache.idsWithStaleDetail() else { return }
        var pending = ids[...]
        await withTaskGroup(of: Void.self) { group in
            func fetchNext() {
                guard !Task.isCancelled, let id = pending.popFirst() else { return }
                group.addTask { try? await self.loadDetail(id: id, generation: generation) }
            }
            for _ in 0..<maxConcurrentDetailFetches {
                fetchNext()
            }
            for await _ in group {
                fetchNext()
            }
        }
    }

    /// Created on another device: listed with its detail, thumbnail drawn from the track
    /// until the next resync brings the server's (like `SaveItinerary`).
    private func loadNewItinerary(id: ItineraryID, generation: Int) async {
        guard let detail = try? await repository.detail(id: id), self.generation == generation else { return }
        try? await cache.save(detail, mapPolyline: detail.track.mapPolyline())
    }

    private func loadDetail(id: ItineraryID, generation: Int) async throws(ItineraryError) {
        let detail: ItineraryDetail
        do {
            detail = try await repository.detail(id: id)
        } catch {
            if error == .notFound, self.generation == generation {
                try? await cache.delete(id: id)
            }
            throw error
        }
        guard self.generation == generation else { return }
        do {
            try await cache.store(detail)
        } catch {
            throw .server(code: "local_cache")
        }
    }
}
