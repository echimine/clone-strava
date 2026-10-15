import Foundation
@testable import StravaClone

/// Builds a timestamped stream of auto-pause signals due north, one fix per second.
struct SyntheticTrace {
    private(set) var now: Date
    private(set) var signals: [AutoPauseSignal] = []
    private var north: Double = 0
    private let origin = Coordinate(latitude: 45.764, longitude: 4.8357)
    private var positions: [Date: Coordinate] = [:]

    init(start: Date) {
        now = start
        positions[start] = origin
    }

    func coordinate(at date: Date) -> Coordinate? {
        positions[date]
    }

    /// One fix per second, `speed` meters further each time; `reportedSpeed` is the GPS speed
    /// (`nil` = Core Location's -1), the actual speed when omitted.
    mutating func move(seconds: Int, speed: Double, reportedSpeed: Double?? = .none, accuracy: Double = 5) {
        for _ in 0..<seconds {
            north += speed
            fix(speed: reportedSpeed ?? speed, accuracy: accuracy)
        }
    }

    /// One fix per second at the same place.
    mutating func stand(seconds: Int, reportedSpeed: Double? = 0, every interval: Int = 1) {
        for _ in 0..<(seconds / interval) {
            fix(speed: reportedSpeed, advancing: TimeInterval(interval))
        }
    }

    /// One fix per second off the athlete's place by each offset (meters north, negative
    /// south) while the athlete stays put: a GPS that trembles.
    mutating func tremble(_ offsets: [Double], reportedSpeed: Double? = 0) {
        for offset in offsets {
            north += offset
            fix(speed: reportedSpeed)
            north -= offset
        }
    }

    /// No fix for `seconds` while still moving at `speed` (a tunnel).
    mutating func gap(seconds: Int, speed: Double) {
        north += speed * Double(seconds)
        now = now.addingTimeInterval(TimeInterval(seconds))
    }

    /// Time passes with no signal at all.
    mutating func wait(seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }

    mutating func motion(_ activity: MotionActivity, confidence: MotionConfidence = .high) {
        signals.append(.motion(MotionReading(activity: activity, confidence: confidence, startDate: now)))
    }

    mutating func stationary() {
        signals.append(.stationary(now))
    }

    private mutating func fix(speed: Double?, accuracy: Double = 5, advancing interval: TimeInterval = 1) {
        now = now.addingTimeInterval(interval)
        let coordinate = origin.offset(northMeters: north)
        positions[now] = coordinate
        signals.append(.location(LocationSample(
            coordinate: coordinate,
            altitude: nil,
            horizontalAccuracy: accuracy,
            speed: speed,
            timestamp: now
        )))
    }
}

enum AutoPauseReplay {
    /// Every decision of the rule over `signals`, from a Recording moving since `since`.
    static func run(_ signals: [AutoPauseSignal], rule: AutoPauseRule, since: Date) -> [AutoPauseDecision] {
        var detector = AutoPauseDetector(rule: rule, monitoringSince: since)
        return signals.compactMap { detector.observe($0) }
    }
}
