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
