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
    private var restoring: Task<Void, any Error>?
    private var observers: [UUID: AsyncStream<RecordingSnapshot?>.Continuation] = [:]

    /// How long points may fail to reach the disk before the athlete is warned (ADR-031 §10).
    static let writeFailureWarningDelay: TimeInterval = 30

    // Automatic Pause (ADR-031 §4)
    private let motionProvider: (any MotionActivityProvider)?
    private let autoPauseFeedback: (any AutoPauseFeedback)?
    private var autoPause: AutoPauseDetector?
    /// Points received during an automatic Pause, written once its end is known.
    private var heldPoints: [LocationSample] = []
    private var motionConsumer: Task<Void, Never>?

    init(
        locationProvider: any LocationProvider,
        repository: any RecordingRepository,
        now: @escaping @Sendable () -> Date = Date.init,
        motionProvider: (any MotionActivityProvider)? = nil,
        autoPauseFeedback: (any AutoPauseFeedback)? = nil
    ) {
        self.locationProvider = locationProvider
        self.repository = repository
        self.now = now
        self.motionProvider = motionProvider
        self.autoPauseFeedback = autoPauseFeedback
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

    /// Picks up a stored Recording once per launch, GPS and background session included
    /// (ADR-031 §3, §10): in its saved phase after a background relaunch, in a Pause from the
    /// last written point when the athlete opens an `active` one. Later calls wait for the first.
    func restore(_ launch: RecordingLaunch = .openedByAthlete) async throws -> RecordingSnapshot? {
        if let snapshot { return snapshot }
        if let restoring {
            try await restoring.value
            return snapshot
        }
        let task = Task { try await self.load(after: launch) }
        restoring = task
        do {
            try await task.value
        } catch {
            restoring = nil
            throw error
        }
        return snapshot
    }

    /// - Parameter autoPause: the auto-pause switch, ignored for a sport without one.
    func start(sport: RecordingSport, autoPause: Bool = false) async throws -> RecordingSnapshot {
        let enabled = autoPause && sport.autoPauseRule != nil
        let recording = Recording(sport: sport, startedAt: now(), autoPauseEnabled: enabled)
        try await repository.create(recording)
        let snapshot = RecordingSnapshot(recording: recording)
        begin(snapshot, points: [])
        await startGPS()
        await armAutoPause()
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
            // After a manual Resume, the rules keep watching (ADR-031 §4).
            heldPoints = []
            autoPause?.monitor(since: resumed.recording.movingSince)
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

    /// Wipes the Recording, its points and its Pauses, and releases the GPS.
    func delete() async throws {
        guard let id = snapshot?.recording.id else { return }
        try await repository.delete(id)
        consumer?.cancel()
        consumer = nil
        disarmAutoPause()
        await locationProvider.endBackgroundTracking()
        snapshot = nil
        distance = nil
        unwrittenPoints = []
        publish()
    }

    // MARK: - Internals

    private func load(after launch: RecordingLaunch) async throws {
        guard let stored = try await repository.load() else { return }
        let recording = stored.resumed(after: launch)
        if recording != stored.recording {
            try await repository.save(recording)
        }
        begin(RecordingSnapshot(recording: recording, points: stored.points), points: stored.points)
        await startGPS()
        await armAutoPause()
    }

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
        guard snapshot != nil else { return }
        if let sample = update.sample {
            snapshot?.position = sample
            if snapshot?.recording.isAutomaticallyPaused == true, autoPause != nil {
                heldPoints.append(sample)
            }
            await record(sample)
            await observe(.location(sample))
        }
        if update.isStationary {
            await observe(.stationary(update.sample?.timestamp ?? now()))
        }
    }

    /// Writes a point of the Recording in progress and adds it to the stats.
    private func record(_ sample: LocationSample) async {
        guard let recording = snapshot?.recording else { return }
        // A Pause writes nothing; a fix older than Start or Resume is a stale one.
        guard recording.phase == .active, sample.timestamp >= recording.movingSince else {
            publish()
            return
        }
        await write(sample, to: recording.id)
        guard snapshot?.recording.id == recording.id else { return }
        snapshot?.pointCount += 1
        snapshot?.isTraceWriteFailing = isWriteFailing
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

    // MARK: - Automatic Pause

    func setAutoPause(_ enabled: Bool) async throws -> RecordingSnapshot? {
        guard snapshot?.recording.sport.autoPauseRule != nil else { return snapshot }
        let updated = try await change { $0.autoPauseEnabled = enabled }
        await armAutoPause()
        return updated
    }

    /// Starts the rules for the Recording in progress if its switch is on, Core Motion included
    /// for a run; an automatic Pause read back from storage stays automatic.
    private func armAutoPause() async {
        disarmAutoPause()
        guard let recording = snapshot?.recording, recording.autoPauseEnabled,
              let rule = recording.sport.autoPauseRule
        else { return }
        if recording.isAutomaticallyPaused, let start = recording.currentPauseStartedAt {
            autoPause = AutoPauseDetector(rule: rule, pausedAt: start, position: recording.currentPausePosition)
        } else {
            autoPause = AutoPauseDetector(rule: rule, monitoringSince: max(now(), recording.movingSince))
        }
        if rule == .motion, let motionProvider {
            let readings = await motionProvider.readings()
            motionConsumer = Task {
                for await reading in readings {
                    await self.observe(.motion(reading))
                }
            }
        }
    }

    private func disarmAutoPause() {
        motionConsumer?.cancel()
        motionConsumer = nil
        autoPause = nil
        heldPoints = []
    }

    /// Feeds the rules while moving or in an automatic Pause; a manual Pause only ends manually.
    private func observe(_ signal: AutoPauseSignal) async {
        guard let recording = snapshot?.recording,
              recording.phase == .active || recording.isAutomaticallyPaused,
              let decision = autoPause?.observe(signal)
        else { return }
        switch decision {
        case let .pause(date, position):
            guard recording.phase == .active else { return }
            heldPoints = []
            guard (try? await change({ $0.pause(at: date, kind: .automatic, position: position) })) != nil else {
                return await armAutoPause()
            }
            await autoPauseFeedback?.autoPauseStarted()
        case let .resume(departure):
            guard recording.isAutomaticallyPaused else { return }
            let held = heldPoints.filter { $0.timestamp >= departure }
            heldPoints = []
            guard let resumed = try? await change({ $0.resume(at: departure) }) else {
                return await armAutoPause()
            }
            distance?.notePause()
            snapshot?.currentSpeed.reset(movingSince: resumed.recording.movingSince)
            for point in held {
                await record(point)
            }
            publish()
            await autoPauseFeedback?.autoPauseEnded()
        }
    }

    /// Points have failed to reach the disk for the warning delay, measured on their own times.
    private var isWriteFailing: Bool {
        guard let first = unwrittenPoints.first, let last = unwrittenPoints.last else { return false }
        return last.timestamp.timeIntervalSince(first.timestamp) >= Self.writeFailureWarningDelay
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
