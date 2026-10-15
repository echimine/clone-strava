import Foundation

/// Which signal decides an automatic Pause (ADR-031 §4): GPS on a bike, smoothed Core Motion
/// on foot.
enum AutoPauseRule: Sendable {
    case gps, motion
}

/// One timestamped input of the automatic Pause rules.
enum AutoPauseSignal: Equatable, Sendable {
    case location(LocationSample)
    /// Core Location's `isStationary`.
    case stationary(Date)
    case motion(MotionReading)
}

extension AutoPauseSignal {
    var date: Date {
        switch self {
        case let .location(sample): sample.timestamp
        case let .stationary(date): date
        case let .motion(reading): reading.startDate
        }
    }
}

enum AutoPauseDecision: Equatable, Sendable {
    /// Start the automatic Pause at the detection, at the athlete's position.
    case pause(at: Date, position: Coordinate?)
    /// End it at the actual departure.
    case resume(at: Date)
}

/// The automatic Pause rules (ADR-031 §4): a pure function of timestamped samples, never a
/// timer. Feed it every signal in time order; it answers when the Recording must pause or
/// resume. No points is not a stop: a tunnel or a GPS loss changes nothing.
struct AutoPauseDetector: Sendable {
    // MARK: Thresholds

    /// Cycling: a moving point has a valid speed at or above this.
    static let movingSpeedMs = 1.0
    /// Cycling: pause after this long without a moving point.
    static let stillDelay: TimeInterval = 10
    /// Cycling, every speed unknown: pause when the movement over `stillDelay` stays below this.
    static let unknownSpeedMaxMovementM = 15.0
    /// Resume on a point this far from the Pause position with a valid speed of `resumeSpeedMs`…
    static let resumeDistanceM = 20.0
    static let resumeSpeedMs = 1.5
    /// …or this far whatever the speed.
    static let resumeAnySpeedDistanceM = 40.0
    /// Fixes less accurate than this are ignored, as for the live stats.
    static let maxAccuracyM = ProvisionalDistance.maxAccuracyM
    /// Running: pause after this long without `running`…
    static let motionWindow: TimeInterval = 5
    /// …with `stationary` at least this long within it…
    static let minimumStationary: TimeInterval = 4
    /// …and no valid GPS speed at or above this within it.
    static let runningGPSSpeedMs = 2.0
    /// Running: resume after this long of continuous `walking`.
    static let walkingResumeDelay: TimeInterval = 3
    /// How long the positions are kept for the rules.
    private static let memory: TimeInterval = 60

    let rule: AutoPauseRule
    /// Start of the stretch watched for a stop (Start, Resume, switch turned on).
    private var monitoringSince: Date
    private var pause: Pause?
    /// Accurate fixes of the last `memory` seconds, oldest first.
    private var recent: [LocationSample] = []
    /// Core Motion readings above low confidence, oldest first: each holds until the next one.
    private var readings: [MotionReading] = []
    /// Time of the latest signal.
    private var clock: Date

    private struct Pause: Sendable {
        let start: Date
        var position: Coordinate?
        /// Accurate fixes received during the Pause, to date the departure.
        var held: [LocationSample] = []
    }

    init(rule: AutoPauseRule, monitoringSince since: Date) {
        self.rule = rule
        monitoringSince = since
        clock = since
    }

    var isPaused: Bool { pause != nil }

    mutating func observe(_ signal: AutoPauseSignal) -> AutoPauseDecision? {
        let now = max(clock, signal.date)
        clock = now
        switch signal {
        case let .location(sample):
            guard Self.isAccurate(sample) else { break }
            remember(sample)
            if pause != nil {
                pause?.held.append(sample)
                if let decision = resumeOnGPS(sample) { return decision }
            } else if rule == .gps {
                return pauseOnGPS(sample)
            }
        case let .stationary(date):
            guard pause == nil, date >= monitoringSince else { return nil }
            return startPause(at: date, position: recent.last?.coordinate)
        case let .motion(reading):
            // Low-confidence readings are ignored: the previous reading still holds.
            guard rule == .motion, reading.confidence > .low else { break }
            remember(reading)
            if pause != nil, reading.activity == .running {
                return endPause(at: reading.startDate)
            }
        }
        guard rule == .motion else { return nil }
        return pause == nil ? pauseOnMotion(at: now) : resumeOnWalking(at: now)
    }

    // MARK: - Cycling (GPS)

    private mutating func pauseOnGPS(_ sample: LocationSample) -> AutoPauseDecision? {
        let now = sample.timestamp
        let watched = recent.filter { $0.timestamp >= monitoringSince }
        let lastMoving = watched.last { ($0.speed ?? 0) >= Self.movingSpeedMs }?.timestamp ?? monitoringSince
        guard now.timeIntervalSince(lastMoving) >= Self.stillDelay else { return nil }
        let windowStart = now.addingTimeInterval(-Self.stillDelay)
        let window = watched.filter { $0.timestamp > windowStart }
        if !window.contains(where: { $0.speed != nil }) {
            // Every speed unknown: only a position that stays put shows a stop.
            guard let anchor = watched.last(where: { $0.timestamp <= windowStart }),
                  window.allSatisfy({
                      $0.coordinate.distance(to: anchor.coordinate).meters < Self.unknownSpeedMaxMovementM
                  })
            else { return nil }
        }
        return startPause(at: now, position: sample.coordinate)
    }

    private mutating func resumeOnGPS(_ sample: LocationSample) -> AutoPauseDecision? {
        guard let position = pause?.position else {
            pause?.position = sample.coordinate
            return nil
        }
        let distance = sample.coordinate.distance(to: position).meters
        let resumes = distance >= Self.resumeAnySpeedDistanceM
            || (distance >= Self.resumeDistanceM && (sample.speed ?? 0) >= Self.resumeSpeedMs)
        guard resumes, let held = pause?.held else { return nil }
        // The departure: the first of the points that keep moving away from the Pause position.
        var index = held.count - 1
        while index > 0,
              held[index - 1].coordinate.distance(to: position) < held[index].coordinate.distance(to: position) {
            index -= 1
        }
        return endPause(at: held[index].timestamp)
    }

    // MARK: - Running (smoothed Core Motion)

    private mutating func pauseOnMotion(at now: Date) -> AutoPauseDecision? {
        guard now.timeIntervalSince(monitoringSince) >= Self.motionWindow else { return nil }
        let windowStart = now.addingTimeInterval(-Self.motionWindow)
        var stationary: TimeInterval = 0
        for (index, reading) in readings.enumerated() {
            let from = max(reading.startDate, windowStart)
            let to = min(index + 1 < readings.count ? readings[index + 1].startDate : now, now)
            guard to > from else { continue }
            if reading.activity == .running { return nil }
            if reading.activity == .stationary { stationary += to.timeIntervalSince(from) }
        }
        guard stationary >= Self.minimumStationary,
              !recent.contains(where: { $0.timestamp > windowStart && ($0.speed ?? 0) >= Self.runningGPSSpeedMs })
        else { return nil }
        return startPause(at: now, position: recent.last?.coordinate)
    }

    private mutating func resumeOnWalking(at now: Date) -> AutoPauseDecision? {
        guard let start = pause?.start, readings.last?.activity == .walking else { return nil }
        var walkingSince = now
        for reading in readings.reversed() {
            guard reading.activity == .walking else { break }
            walkingSince = reading.startDate
        }
        let from = max(walkingSince, start)
        guard now.timeIntervalSince(from) >= Self.walkingResumeDelay else { return nil }
        return endPause(at: from)
    }

    // MARK: - Pause and resume

    private mutating func startPause(at date: Date, position: Coordinate?) -> AutoPauseDecision {
        pause = Pause(start: date, position: position)
        return .pause(at: date, position: position)
    }

    private mutating func endPause(at departure: Date) -> AutoPauseDecision? {
        guard let start = pause?.start else { return nil }
        // A Pause ends strictly after it starts (trace v2).
        let end = max(departure, start.addingTimeInterval(0.001))
        pause = nil
        monitoringSince = end
        return .resume(at: end)
    }

    private mutating func remember(_ sample: LocationSample) {
        recent.append(sample)
        let horizon = sample.timestamp.addingTimeInterval(-Self.memory)
        recent.removeAll { $0.timestamp < horizon }
    }

    private mutating func remember(_ reading: MotionReading) {
        readings.append(reading)
        let horizon = clock.addingTimeInterval(-Self.memory)
        while readings.count > 1, readings[1].startDate <= horizon {
            readings.removeFirst()
        }
    }

    private static func isAccurate(_ sample: LocationSample) -> Bool {
        sample.horizontalAccuracy >= 0 && sample.horizontalAccuracy <= maxAccuracyM
    }
}
