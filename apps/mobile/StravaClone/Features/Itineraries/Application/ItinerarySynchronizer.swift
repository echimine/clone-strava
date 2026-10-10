import Foundation

/// Keeps the cache equal to the athlete's Itineraries on the server (ADR-030 §8): the full
/// list, every page, is read again on each trigger (foreground, Mes Itinéraires opening,
/// pull-to-refresh, network back) and the local rows no longer returned are deleted. Then
/// every detail whose Itinerary changed (or is new) is fetched, so any detail opens offline.
/// Triggers arriving during a resync join it. #38 drains its queue on the same triggers.
@MainActor
final class ItinerarySynchronizer {
    private let repository: any ItineraryRepository
    private let cache: any ItineraryCache
    private var running: Task<Result<Void, ItineraryError>, Never>?
    /// Bumped by sign-out: a resync started before must not write anything.
    private var generation = 0
    /// Details fetched at the same time after a resync.
    private let maxConcurrentDetailFetches: Int

    init(repository: any ItineraryRepository, cache: any ItineraryCache, maxConcurrentDetailFetches: Int = 4) {
        self.repository = repository
        self.cache = cache
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

    /// Sign-out: drops the resync in flight and wipes the cache (#38 adds the queue).
    func signOut() async {
        generation += 1
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
