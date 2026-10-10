import Foundation

/// Renews the session after a `401` before a queued operation is tried again (ADR-008 §5).
/// Shared by every feature that drains the `sync_operation` queue.
protocol SessionRefreshing: Sendable {
    /// `true` when the session is valid again (possibly under a new token), `false` when the
    /// athlete must sign in again.
    func refresh() async -> Bool
}
