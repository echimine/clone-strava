import Foundation

/// The Live Activity of the Recording in progress (ADR-031 §9, §15): lock screen and Dynamic
/// Island. Local updates only. A refused or failed Live Activity never blocks the Recording,
/// so nothing here throws.
protocol RecordingLiveActivity: Sendable {
    /// Ends every Live Activity a previous run of the app left behind.
    func endAll() async
    /// - Returns: `false` when iOS refused it (Live Activities off, limit reached, app in the
    ///   background) or it failed.
    func start(_ content: RecordingLiveActivityContent, staleDate: Date) async -> Bool
    func update(_ content: RecordingLiveActivityContent, staleDate: Date) async
    /// Save: `final` stays until iOS removes it. Delete: `nil` removes it at once.
    func end(final content: RecordingLiveActivityContent?) async
}

/// What the Live Activity shows of a Recording at one instant (ADR-031 §9): plain values.
struct RecordingLiveActivityContent: Equatable, Sendable {
    /// State of the followed Itinerary, shown next to the distance left.
    enum ItineraryState: Equatable, Sendable {
        /// No position within 50 m of the track yet: distance left shows "—".
        case notSnapped
        case onTrack
        case offTrack
        /// "Chemin recalculé" (ADR-031 §7).
        case returnPath
        case finished
    }

    struct Itinerary: Equatable, Sendable {
        let name: String
        /// `nil` before the first snap.
        let remaining: Distance?
        /// Share of the track done, 0 to 1.
        let fraction: Double
        let state: ItineraryState
        /// The Return path shown: tells a new Return path from the previous one, even to the
        /// same return point. Not sent to the widget.
        var returnPath: ReturnPath? = nil
    }

    let sport: RecordingSport
    /// Start moved forward by the finished Pauses: a timer counting from here shows the time
    /// minus Pauses.
    let timerStart: Date
    /// Start of the Pause in progress: the timer stops there.
    let pausedAt: Date?
    let distance: Distance
    /// On foot, `nil` while not meaningful.
    let averagePace: Duration?
    /// On a bike, `nil` during a Pause.
    let currentSpeedMs: Double?
    let averageSpeedMs: Double
    let itinerary: Itinerary?
    /// Final content after Save: "<sport> enregistrée".
    var isSaved = false

    init(_ snapshot: RecordingSnapshot, at now: Date) {
        let recording = snapshot.recording
        let stats = snapshot.stats(at: now)
        let paused = recording.pauses.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        sport = recording.sport
        timerStart = recording.startedAt.addingTimeInterval(paused)
        pausedAt = recording.currentPauseStartedAt
        distance = snapshot.distance
        averagePace = stats.averagePace
        currentSpeedMs = stats.currentSpeedMs
        averageSpeedMs = stats.averageSpeedMs
        itinerary = snapshot.itinerary.map { followed in
            Itinerary(
                name: followed.name,
                remaining: followed.remaining,
                fraction: followed.progress.fraction,
                state: ItineraryState(followed.state),
                returnPath: followed.returnPath
            )
        }
    }

    var isPaused: Bool { pausedAt != nil }

    /// A Pause, a Resume, an Itinerary state change, a Return path arriving, replacing another
    /// or disappearing, or the Itinerary's removal shows at once (ADR-031 §9); anything else waits for the next 5 s
    /// update.
    func needsImmediateUpdate(after previous: Self) -> Bool {
        isPaused != previous.isPaused || itinerary?.state != previous.itinerary?.state
            || itinerary?.returnPath != previous.itinerary?.returnPath
    }
}

private extension RecordingLiveActivityContent.ItineraryState {
    init(_ state: FollowedItinerary.State) {
        switch state {
        case .notSnapped: self = .notSnapped
        case .onTrack: self = .onTrack
        case .offTrack: self = .offTrack
        case .returnPath: self = .returnPath
        case .finished: self = .finished
        }
    }
}
