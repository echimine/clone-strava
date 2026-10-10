import Foundation

/// Exponential backoff between retries: routing saturated (`429`, ADR-030 §2), queued changes (§8):
/// `initialDelay`, then twice as long each time, never more than `maxDelay`.
struct RetryBackoff: Equatable, Sendable {
    var initialDelay: Duration = .seconds(2)
    var maxDelay: Duration = .seconds(60)

    /// Delay before retry number `attempt`, counted from 0.
    func delay(beforeRetry attempt: Int) -> Duration {
        var delay = initialDelay
        for _ in 0 ..< attempt where delay < maxDelay {
            delay *= 2
        }
        return min(delay, maxDelay)
    }
}
