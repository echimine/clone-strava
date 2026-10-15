import Foundation

/// Runs the Recording in progress (ADR-031 §1, §3, §10): one GPS stream with a background
/// session from Start to Delete (never stopped in a Pause), each raw point written as it
/// arrives outside Pauses, provisional distance and current speed. An actor: it holds the
/// shared state of the Recording (ADR-007).
actor RecordingService {
    private let locationProvider: any LocationProvider
    private let repository: any RecordingRepository
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void

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

    /// Lock screen and Dynamic Island (ADR-031 §9): told of every change, never waited for.
    private let liveActivity: RecordingLiveActivityUpdater?

    // Return path (ADR-031 §7)
    private let returnPathRouter: (any ReturnPathRouter)?
    /// `true` while a network route exists (`NWPathMonitor`), current state first.
    private let connectivity: (@Sendable () async -> AsyncStream<Bool>)?
    private var returnPathRequest: Task<Void, Never>?
    /// Sends a wanted request once its delay is over, even if no fix comes (ADR-031 §7).
    private var returnPathRetry: (date: Date, task: Task<Void, Never>)?
    private var connectivityConsumer: Task<Void, Never>?

    init(
        locationProvider: any LocationProvider,
        repository: any RecordingRepository,
        now: @escaping @Sendable () -> Date = Date.init,
        motionProvider: (any MotionActivityProvider)? = nil,
        autoPauseFeedback: (any AutoPauseFeedback)? = nil,
        liveActivity: RecordingLiveActivityUpdater? = nil,
        returnPathRouter: (any ReturnPathRouter)? = nil,
        connectivity: (@Sendable () async -> AsyncStream<Bool>)? = nil,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.locationProvider = locationProvider
        self.repository = repository
        self.now = now
        self.motionProvider = motionProvider
        self.autoPauseFeedback = autoPauseFeedback
        self.liveActivity = liveActivity
        self.returnPathRouter = returnPathRouter
        self.connectivity = connectivity
        self.sleep = sleep
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

    /// - Parameters:
    ///   - itinerary: the copy of the chosen Itinerary loaded from the cache, kept until the end
    ///     even if it is deleted elsewhere (ADR-031 §2).
    ///   - autoPause: the auto-pause switch, ignored for a sport without one.
    func start(
        sport: RecordingSport,
        itinerary: FollowedItinerary? = nil,
        autoPause: Bool = false
    ) async throws -> RecordingSnapshot {
        let enabled = autoPause && sport.autoPauseRule != nil
        let recording = Recording(sport: sport, startedAt: now(), autoPauseEnabled: enabled)
        try await repository.create(recording)
        if let itinerary {
            try await repository.saveItinerary(itinerary, of: recording.id)
        }
        let snapshot = RecordingSnapshot(recording: recording, itinerary: itinerary)
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
        disarmAutoPause()
        stopReturnPaths()
        await locationProvider.endBackgroundTracking()
        liveActivity?.send(.saved(snapshot))
        self.snapshot = nil
        distance = nil
        unwrittenPoints = []
        publish()
    }

    /// "Retirer l'Itinéraire" (ADR-031 §2, §8): stops following it; it can never be replaced.
    func removeItinerary() async throws -> RecordingSnapshot? {
        guard let id = snapshot?.recording.id, snapshot?.itinerary != nil else { return snapshot }
        try await repository.saveItinerary(nil, of: id)
        snapshot?.itinerary = nil
        returnPathRequest?.cancel()
        returnPathRequest = nil
        scheduleReturnPathRetry()
        publish()
        return snapshot
    }

    /// Wipes the Recording, its points and its Pauses, and releases the GPS.
    func delete() async throws {
        guard let id = snapshot?.recording.id else { return }
        try await repository.delete(id)
        consumer?.cancel()
        consumer = nil
        disarmAutoPause()
        stopReturnPaths()
        await locationProvider.endBackgroundTracking()
        liveActivity?.send(.deleted(id))
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
        begin(
            RecordingSnapshot(recording: recording, points: stored.points, itinerary: stored.itinerary),
            points: stored.points
        )
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
        await observeConnectivity()
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
            await followItinerary(sample)
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
        if let hop = distance?.append(sample) {
            snapshot?.currentSpeed.record(hop, at: sample.timestamp)
        }
        snapshot?.distance = distance?.total ?? .zero
        publish()
    }

    /// Itinerary progress and Return path follow the real position, during a Pause too, and are
    /// saved on each change (ADR-031 §6, §7, §10). A failed save is caught up by the next one.
    private func followItinerary(_ sample: LocationSample) async {
        guard let id = snapshot?.recording.id, var itinerary = snapshot?.itinerary else { return }
        let before = itinerary
        let command = itinerary.follow(sample)
        snapshot?.itinerary = itinerary
        run(command)
        if itinerary.progress.saved != before.progress.saved {
            try? await repository.saveItineraryProgress(itinerary.progress.saved, of: id)
        }
        if itinerary.returnPath != before.returnPath {
            try? await repository.saveReturnPath(itinerary.returnPath, of: id)
        }
    }

    // MARK: - Return path (ADR-031 §7)

    private func run(_ command: ReturnPathCommand?) {
        defer { scheduleReturnPathRetry() }
        switch command {
        case nil:
            return
        case .cancel:
            returnPathRequest?.cancel()
            returnPathRequest = nil
        case let .send(request):
            guard let router = returnPathRouter, let profile = snapshot?.recording.sport.routingProfile else { return }
            returnPathRequest?.cancel()
            returnPathRequest = Task {
                do {
                    let routed = try await router.returnPath(
                        from: request.position,
                        to: request.returnPoint.coordinate,
                        profile: profile,
                        bearing: request.bearing
                    )
                    await self.returnPathArrived(routed, for: request)
                } catch is CancellationError {
                    // Back on the track, Itinerary removed or Recording over.
                } catch {
                    await self.returnPathFailed(error as? RoutingError ?? .temporary, for: request)
                }
            }
        }
    }

    private func returnPathArrived(_ routed: RoutedReturnPath, for request: ReturnPathRequest) async {
        guard let id = snapshot?.recording.id, var itinerary = snapshot?.itinerary,
              itinerary.returnPathArrived(routed, for: request)
        else { return }
        snapshot?.itinerary = itinerary
        returnPathRequest = nil
        try? await repository.saveReturnPath(itinerary.returnPath, of: id)
        publish()
    }

    private func returnPathFailed(_ error: RoutingError, for request: ReturnPathRequest) async {
        guard let id = snapshot?.recording.id, var itinerary = snapshot?.itinerary,
              itinerary.returnPathFailed(error, for: request, at: now())
        else { return }
        let hadPath = snapshot?.itinerary?.returnPath != nil
        snapshot?.itinerary = itinerary
        returnPathRequest = nil
        scheduleReturnPathRetry()
        if hadPath, itinerary.returnPath == nil {
            try? await repository.saveReturnPath(nil, of: id)
        }
        publish()
    }

    /// Follows the date at which a wanted request may leave: one timer, replaced when the date
    /// changes, cancelled when nothing waits (re-snapping, Itinerary removed, Save, Delete).
    private func scheduleReturnPathRetry() {
        let date = snapshot?.itinerary?.returnPathRetryDate
        guard date != returnPathRetry?.date else { return }
        returnPathRetry?.task.cancel()
        returnPathRetry = nil
        guard let date else { return }
        let delay = max(0, date.timeIntervalSince(now()))
        let sleep = sleep
        let task = Task {
            guard (try? await sleep(.seconds(delay))) != nil, !Task.isCancelled else { return }
            await self.returnPathRetryDue()
        }
        returnPathRetry = (date, task)
    }

    private func returnPathRetryDue() {
        returnPathRetry = nil
        guard var itinerary = snapshot?.itinerary else { return }
        let command = itinerary.retryReturnPath(from: snapshot?.position, at: now())
        snapshot?.itinerary = itinerary
        run(command)
    }

    private func observeConnectivity() async {
        connectivityConsumer?.cancel()
        guard let connectivity else { return }
        let changes = await connectivity()
        connectivityConsumer = Task {
            for await isOnline in changes {
                self.connectivityChanged(isOnline)
            }
        }
    }

    private func connectivityChanged(_ isOnline: Bool) {
        guard var itinerary = snapshot?.itinerary else { return }
        let command = itinerary.connectivityChanged(isOnline, lastPosition: snapshot?.position, at: now())
        snapshot?.itinerary = itinerary
        run(command)
    }

    private func stopReturnPaths() {
        returnPathRequest?.cancel()
        returnPathRequest = nil
        returnPathRetry?.task.cancel()
        returnPathRetry = nil
        connectivityConsumer?.cancel()
        connectivityConsumer = nil
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
        if let snapshot {
            liveActivity?.send(.changed(snapshot))
        }
    }

    private func removeObserver(_ id: UUID) {
        observers[id] = nil
    }
}
