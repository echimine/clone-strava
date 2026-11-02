import Foundation

extension Duration {
    /// The same length in seconds, for `Date.addingTimeInterval` (the sync queues' backoff,
    /// ADR-031 §14, ADR-035 §5).
    var timeInterval: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
