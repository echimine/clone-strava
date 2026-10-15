import Foundation

/// What the athlete feels when an automatic Pause starts or ends (ADR-031 §4): a haptic.
protocol AutoPauseFeedback: Sendable {
    func autoPauseStarted() async
    func autoPauseEnded() async
}
