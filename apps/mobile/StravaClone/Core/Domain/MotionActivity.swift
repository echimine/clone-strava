import Foundation

/// What Core Motion says the athlete is doing, in domain types only (no Core Motion).
enum MotionActivity: Equatable, Sendable {
    case stationary, walking, running
    /// Cycling, automotive, unknown or nothing.
    case other
}

enum MotionConfidence: Int, Comparable, Sendable {
    case low, medium, high

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// One Core Motion activity reading: it holds from `startDate` until the next one.
struct MotionReading: Equatable, Sendable {
    let activity: MotionActivity
    let confidence: MotionConfidence
    let startDate: Date
}

/// Core Motion's activity readings (ADR-031 §4), a fake in tests.
protocol MotionActivityProvider: Sendable {
    /// Asks for "Motion & Fitness" access the first time; `false` when refused or unavailable.
    func requestAuthorization() async -> Bool
    /// Readings while the stream is alive.
    func readings() async -> AsyncStream<MotionReading>
}
