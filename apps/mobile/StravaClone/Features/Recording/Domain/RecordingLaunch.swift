import Foundation

/// How the app came back to a stored Recording after it was killed or crashed (ADR-031 §3, §10).
enum RecordingLaunch: Equatable, Sendable {
    /// iOS relaunched the app in the background for location: the Recording goes on in its
    /// saved phase, the gap counts as a GPS loss.
    case relaunchedInBackground
    /// The athlete opened the app after a crash or a forced quit.
    case openedByAthlete
}

extension StoredRecording {
    /// The Recording to pick up (ADR-031 §10). Opened by the athlete, an `active` Recording
    /// reopens paused, the Pause starting at the last written point (never before the current
    /// stretch of movement): nothing of the time the app was dead counts. `paused` and
    /// `finishing` keep their phase.
    func resumed(after launch: RecordingLaunch) -> Recording {
        var resumed = recording
        guard launch == .openedByAthlete, resumed.phase == .active else { return resumed }
        let lastPoint = points.last?.timestamp ?? resumed.movingSince
        resumed.pause(at: max(lastPoint, resumed.movingSince))
        return resumed
    }
}
