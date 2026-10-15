import Foundation

/// Phase of a Recording (ADR-031 §1). A Recording is not an Activity state: it only
/// becomes an Activity when saved.
enum RecordingPhase: String, Codable, Sendable {
    case active, paused, finishing
}

/// A finished Pause of a Recording (ADR-031 §4, §12): no kind once finished.
struct RecordingPause: Equatable, Sendable {
    let start: Date
    let end: Date
}

/// The Recording in progress (ADR-031 §1, §5, §10): one at a time, keyed by the UUID of the
/// Activity it may become. Timer, distance and speeds are derived, never stored.
struct Recording: Equatable, Sendable {
    let id: ActivityID
    let sport: RecordingSport
    let startedAt: Date
    private(set) var phase: RecordingPhase
    /// Start of the Pause in progress (`paused` and `finishing`).
    private(set) var currentPauseStartedAt: Date?
    /// Finished Pauses, oldest first.
    private(set) var pauses: [RecordingPause]

    init(id: ActivityID = ActivityID(), sport: RecordingSport, startedAt: Date) {
        self.init(id: id, sport: sport, startedAt: startedAt, phase: .active, currentPauseStartedAt: nil, pauses: [])
    }

    /// A Recording read back from storage.
    init(
        id: ActivityID,
        sport: RecordingSport,
        startedAt: Date,
        phase: RecordingPhase,
        currentPauseStartedAt: Date?,
        pauses: [RecordingPause]
    ) {
        self.id = id
        self.sport = sport
        self.startedAt = startedAt
        self.phase = phase
        self.currentPauseStartedAt = phase == .active ? nil : currentPauseStartedAt
        self.pauses = pauses
    }

    var isPaused: Bool { phase != .active }

    /// End of the Activity once finished (ADR-031 §11): the start of the final Pause, which is
    /// never sent.
    var endedAt: Date? {
        phase == .finishing ? currentPauseStartedAt : nil
    }

    /// Start of the current stretch of movement: Start, or the end of the last Pause.
    var movingSince: Date {
        pauses.last?.end ?? startedAt
    }

    mutating func pause(at date: Date) {
        guard phase == .active else { return }
        phase = .paused
        currentPauseStartedAt = date
    }

    /// Ends the Pause in progress and returns it, to be stored with the points.
    @discardableResult
    mutating func resume(at date: Date) -> RecordingPause? {
        guard phase == .paused, let start = currentPauseStartedAt else { return nil }
        let pause = RecordingPause(start: start, end: max(date, start))
        phase = .active
        currentPauseStartedAt = nil
        pauses.append(pause)
        return pause
    }

    /// Finish exists only in a Pause (ADR-031 §8): the Pause stays open on the finish screen.
    mutating func finish() {
        guard phase == .paused else { return }
        phase = .finishing
    }

    /// "Reprendre" on the finish screen: back to the Pause, which keeps running.
    mutating func reopen() {
        guard phase == .finishing else { return }
        phase = .paused
    }

    /// The timer (ADR-031 §5): time since Start minus Pauses, frozen during a Pause.
    func elapsed(at now: Date) -> Duration {
        let end = currentPauseStartedAt ?? now
        let paused = pauses.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        let seconds = max(0, end.timeIntervalSince(startedAt) - paused)
        return .milliseconds(Int64((seconds * 1_000).rounded()))
    }
}
