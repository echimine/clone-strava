import ActivityKit
import Foundation

struct LockTestAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Chrono start, shifted forward on each resume so the timer excludes pauses.
        var timerStart: Date
        var pausedAt: Date?
        var openTaps = 0
        var authTaps = 0
        /// e.g. "14:02:11 · A · background · locked"
        var lastRun = "—"

        var isPaused: Bool { pausedAt != nil }
    }
}
