import Foundation

/// What the Recording service tells its Live Activity, in order.
enum RecordingLiveActivityEvent: Sendable {
    case changed(RecordingSnapshot)
    /// Save: the final content stays until iOS removes it.
    case saved(RecordingSnapshot)
    /// Delete: removed at once.
    case deleted(ActivityID)
    /// Five seconds passed.
    case tick
}

/// Drives the Live Activity of the Recording (ADR-031 §9) from the service's events, one at a
/// time.
actor RecordingLiveActivityUpdater {
    /// Without an update for this long, iOS marks the Live Activity stale.
    static let staleAfter: TimeInterval = 120
    /// Unchanged content is sent again after this long, only to push the stale date back.
    static let staleRefresh: TimeInterval = 60

    private let port: any RecordingLiveActivity
    private let now: @Sendable () -> Date
    private let ticks: @Sendable () -> AsyncStream<Void>
    private let events: AsyncStream<RecordingLiveActivityEvent>
    private let continuation: AsyncStream<RecordingLiveActivityEvent>.Continuation

    /// The Recording shown and its latest state.
    private var current: RecordingSnapshot?
    /// What the Live Activity shows now, `nil` while iOS refuses it.
    private var shown: RecordingLiveActivityContent?
    private var shownAt: Date?
    private var ticker: Task<Void, Never>?
    /// The last Recording saved or deleted: late changes of it are ignored.
    private var ended: ActivityID?

    /// - Parameter ticks: one element every 5 s.
    init(
        port: any RecordingLiveActivity,
        now: @escaping @Sendable () -> Date = Date.init,
        ticks: @escaping @Sendable () -> AsyncStream<Void>
    ) {
        self.port = port
        self.now = now
        self.ticks = ticks
        (events, continuation) = AsyncStream<RecordingLiveActivityEvent>.makeStream()
    }

    /// The live rhythm: one element every 5 s while iterated.
    static func everyFiveSeconds() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let timer = Task {
                while (try? await Task.sleep(for: .seconds(5))) != nil {
                    continuation.yield()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in timer.cancel() }
        }
    }

    /// Called by the service; never waits.
    nonisolated func send(_ event: RecordingLiveActivityEvent) {
        continuation.yield(event)
    }

    /// Ends what a previous run left behind, then follows the events, for the app's lifetime.
    func run() async {
        await port.endAll()
        for await event in events {
            await handle(event)
        }
    }

    private func handle(_ event: RecordingLiveActivityEvent) async {
        switch event {
        case let .changed(snapshot):
            guard snapshot.recording.id != ended else { return }
            guard current?.recording.id == snapshot.recording.id else {
                current = snapshot
                startTicking()
                return await request(snapshot)
            }
            current = snapshot
            if let shown, RecordingLiveActivityContent(snapshot, at: now()).needsImmediateUpdate(after: shown) {
                await update(snapshot)
            }
        case let .saved(snapshot):
            guard current?.recording.id == snapshot.recording.id else { return }
            var content = RecordingLiveActivityContent(snapshot, at: now())
            content.isSaved = true
            stop()
            await port.end(final: content)
        case let .deleted(id):
            guard current?.recording.id == id else { return }
            stop()
            await port.end(final: nil)
        case .tick:
            guard let current else { return }
            // A refused Live Activity is asked again: the app may now be in the foreground.
            guard let shown, let shownAt else { return await request(current) }
            let content = RecordingLiveActivityContent(current, at: now())
            if content != shown || now().timeIntervalSince(shownAt) >= Self.staleRefresh {
                await update(current)
            }
        }
    }

    private func stop() {
        ended = current?.recording.id
        current = nil
        shown = nil
        shownAt = nil
        ticker?.cancel()
        ticker = nil
    }

    private func request(_ snapshot: RecordingSnapshot) async {
        let date = now()
        let content = RecordingLiveActivityContent(snapshot, at: date)
        if await port.start(content, staleDate: date.addingTimeInterval(Self.staleAfter)) {
            shown = content
            shownAt = date
        }
    }

    private func update(_ snapshot: RecordingSnapshot) async {
        let date = now()
        let content = RecordingLiveActivityContent(snapshot, at: date)
        shown = content
        shownAt = date
        await port.update(content, staleDate: date.addingTimeInterval(Self.staleAfter))
    }

    private func startTicking() {
        ticker?.cancel()
        let ticks = ticks()
        let continuation = continuation
        ticker = Task {
            for await _ in ticks {
                continuation.yield(.tick)
            }
        }
    }
}
