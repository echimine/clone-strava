import Foundation

/// Everything the screens show of the Recording in progress, at one point of the stream
/// (ADR-031 §5, §8). The timer ticks on its own: ask `stats(at:)` every second.
struct RecordingSnapshot: Equatable, Sendable {
    var recording: Recording
    var distance: Distance
    /// Coordinates of the accurate written points, for the map.
    var trace: [Coordinate]
    /// Number of written points.
    var pointCount: Int
    /// Last fix, during a Pause too (map position, GPS indicator).
    var position: LocationSample?
    var currentSpeed: CurrentSpeed
    /// The Itinerary followed and the progress along it (ADR-031 §6).
    var itinerary: FollowedItinerary?
    /// Points have failed to reach the disk for 30 s (ADR-031 §10): they are kept in memory and
    /// retried, the Recording goes on, a banner warns the athlete.
    var isTraceWriteFailing = false

    init(
        recording: Recording,
        points: [LocationSample] = [],
        position: LocationSample? = nil,
        itinerary: FollowedItinerary? = nil
    ) {
        self.recording = recording
        self.itinerary = itinerary
        distance = ProvisionalDistance.measure(points, pauses: recording.pauses, sport: recording.sport)
        trace = points.filter(Self.isAccurate).map(\.coordinate)
        pointCount = points.count
        self.position = position
        currentSpeed = CurrentSpeed(movingSince: recording.movingSince)
    }

    static func isAccurate(_ sample: LocationSample) -> Bool {
        sample.horizontalAccuracy >= 0 && sample.horizontalAccuracy <= ProvisionalDistance.maxAccuracyM
    }

    func stats(at now: Date) -> RecordingStats {
        RecordingStats(
            sport: recording.sport,
            elapsed: recording.elapsed(at: now),
            distance: distance,
            currentSpeedMs: recording.isPaused ? nil : currentSpeed.speedMs(at: now)
        )
    }

    /// Why the Activity cannot be saved yet (ADR-031 §11), `nil` when it can.
    var saveBlocker: RecordingSaveBlocker? {
        RecordingSaveBlocker(recording: recording, pointCount: pointCount)
    }
}

/// ADR-031 §11: below the sport's minimum duration or with fewer than 2 points, Save is
/// disabled with an explanation. The minimum distance is ignored, as on the server.
enum RecordingSaveBlocker: Equatable, Sendable {
    case tooShort(minimum: Duration)
    case notEnoughPoints

    init?(recording: Recording, pointCount: Int) {
        let end = recording.endedAt ?? recording.currentPauseStartedAt ?? .distantFuture
        let duration = end.timeIntervalSince(recording.startedAt)
        let minimum = recording.sport.minimumDuration
        if duration < Double(minimum.components.seconds) {
            self = .tooShort(minimum: minimum)
        } else if pointCount < 2 {
            self = .notEnoughPoints
        } else {
            return nil
        }
    }
}
