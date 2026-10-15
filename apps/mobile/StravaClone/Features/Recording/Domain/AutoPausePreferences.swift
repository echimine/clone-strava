import Foundation

/// The auto-pause switch remembered per sport on the device (ADR-031 §4).
protocol AutoPausePreferences: Sendable {
    /// `nil` until the athlete changes it: the sport's default applies.
    func autoPause(for sport: RecordingSport) -> Bool?
    func rememberAutoPause(_ enabled: Bool, for sport: RecordingSport)
}
