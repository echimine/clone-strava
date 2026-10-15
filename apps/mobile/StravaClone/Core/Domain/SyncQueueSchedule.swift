import Foundation

/// When a queued operation of `sync_operation` (ADR-008 §3) may be sent again. The table keeps
/// its dates to the millisecond: an operation queued "now" can read back up to half a
/// millisecond later than the clock, and must still count as due at once.
enum SyncQueueSchedule {
    static let datePrecision: TimeInterval = 0.001

    static func isDue(_ nextAttemptAt: Date, at date: Date) -> Bool {
        nextAttemptAt <= date.addingTimeInterval(datePrecision)
    }
}
