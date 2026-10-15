import Foundation

/// Runs the Recording in progress (ADR-031 §1, §3, §10): one GPS stream with a background
/// session from Start to Delete (never stopped in a Pause), each raw point written as it
/// arrives outside Pauses, provisional distance and current speed. An actor: it holds the
/// shared state of the Recording (ADR-007).
actor RecordingService {
    private let locationProvider: any LocationProvider
    private let repository: any RecordingRepository
    private let now: @Sendable () -> Date

    private var snapshot: RecordingSnapshot?
    private var distance: ProvisionalDistance?
    /// Points whose write failed, retried with the next one: the Recording never stops by itself.
    private var unwrittenPoints: [LocationSample] = []
    private var consumer: Task<Void, Never>?
    private var observers: [UUID: AsyncStream<RecordingSnapshot?>.Continuation] = [:]

    init(
        locationProvider: any LocationProvider,
        repository: any RecordingRepository,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.locationProvider = locationProvider
        self.repository = repository
        self.now = now
    }

    /// The Recording in progress (`nil` when there is none), now and on every change.
    func snapshots() -> AsyncStream<RecordingSnapshot?> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<RecordingSnapshot?>.makeStream()
        continuation.yield(snapshot)
        continuation.onTermination = { _ in
            Task { await self.removeObserver(id) }
        }
        observers[id] = continuation
        return stream
    }

    /// Picks up a stored Recording in its saved phase, GPS and background session included.
    func restore() async throws -> RecordingSnapshot? {
        if let snapshot { return snapshot }
        guard let stored = try await repository.load() else { return nil }
        begin(RecordingSnapshot(recording: stored.recording, points: stored.points), points: stored.points)
        await startGPS()
        return snapshot
    }

    func start(sport: RecordingSport) async throws -> RecordingSnapshot {
        let recording = Recording(sport: sport, startedAt: now())
        try await repository.create(recording)
        let snapshot = RecordingSnapshot(recording: recording)
        begin(snapshot, points: [])
        await startGPS()
        return snapshot
    }

    func pause() async throws -> RecordingSnapshot? {
        try await change { $0.pause(at: now()) }
    }

    func resume() async throws -> RecordingSnapshot? {
        let resumed = try await change { $0.resume(at: now()) }
        if let resumed {
            distance?.notePause()
            snapshot?.currentSpeed.reset(movingSince: resumed.recording.movingSince)
            publish()
        }
        return snapshot
    }

    /// Opens the finish screen; only from a Pause.
    func finish() async throws -> RecordingSnapshot? {
        try await change { $0.finish() }
    }

    /// "Reprendre" on the finish screen: back to the Pause.
    func reopen() async throws -> RecordingSnapshot? {
        try await change { $0.reopen() }
    }

    /// Save (ADR-031 §11), from the finish screen only: `persist` turns the finished Recording
    /// into a local Activity in one transaction that also deletes the `recording` row; then the
    /// GPS and the background session are released and the Record tab returns to the pre-start
    /// screen. Nothing is released if `persist` throws.
    func save(_ persist: @Sendable (RecordingSnapshot) async throws -> Void) async throws {
        guard let snapshot, snapshot.recording.phase == .finishing else { throw RecordingSaveError.notSavable }
        try await persist(snapshot)
        guard self.snapshot?.recording.id == snapshot.recording.id else { return }
        consumer?.cancel()
        consumer = nil
        await locationProvider.endBackgroundTracking()
        self.snapshot = nil
        distance = nil
        unwrittenPoints = []
        publish()
    }

    /// Wipes the Recording, its points and its Pauses, and releases the GPS.
    func delete() async throws {
        guard let id = snapshot?.recording.id else { return }
        try await repository.delete(id)
        consumer?.cancel()
        consumer = nil
        await locationProvider.endBackgroundTracking()
        snapshot = nil
        distance = nil
        unwrittenPoints = []
        publish()
    }

    // MARK: - Internals

    private func begin(_ snapshot: RecordingSnapshot, points: [LocationSample]) {
        let recording = snapshot.recording
        distance = ProvisionalDistance.replaying(points, pauses: recording.pauses, sport: recording.sport)
        self.snapshot = snapshot
        publish()
    }

    private func startGPS() async {
        await locationProvider.beginBackgroundTracking()
        let updates = await locationProvider.updates()
        consumer?.cancel()
        consumer = Task {
            for await update in updates {
                await self.handle(update)
            }
        }
    }

    private func change(_ mutation: (inout Recording) -> Void) async throws -> RecordingSnapshot? {
        guard var recording = snapshot?.recording else { return nil }
        mutation(&recording)
        guard recording != snapshot?.recording else { return snapshot }
        try await repository.save(recording)
        snapshot?.recording = recording
        publish()
        return snapshot
    }

    private func handle(_ update: LocationUpdate) async {
        guard var current = snapshot, let sample = update.sample else { return }
        current.position = sample
        snapshot = current
        let recording = current.recording
        // A Pause writes nothing; a fix older than Start or Resume is a stale one.
        guard recording.phase == .active, sample.timestamp >= recording.movingSince else {
            publish()
            return
        }
        await write(sample, to: recording.id)
        guard snapshot?.recording.id == recording.id else { return }
        snapshot?.pointCount += 1
        if RecordingSnapshot.isAccurate(sample) {
            snapshot?.trace.append(sample.coordinate)
        }
        if let leg = distance?.append(sample) {
            snapshot?.currentSpeed.record(leg, at: sample.timestamp)
        }
        snapshot?.distance = distance?.total ?? .zero
        publish()
    }

    private func write(_ sample: LocationSample, to id: ActivityID) async {
        unwrittenPoints.append(sample)
        do {
            while let point = unwrittenPoints.first {
                try await repository.append(point, to: id)
                unwrittenPoints.removeFirst()
            }
        } catch {
            // Kept in memory and retried with the next point (ADR-031 §10).
        }
    }

    private func publish() {
        for continuation in observers.values {
            continuation.yield(snapshot)
        }
    }

    private func removeObserver(_ id: UUID) {
        observers[id] = nil
    }
}
