import Foundation

/// Sends product events (ADR-015). Features depend on this port only, never on the SDK:
/// PostHog in the app (`PostHogAnalyticsClient`), a fake in tests.
protocol AnalyticsClient: Sendable {
    func capture(_ event: AnalyticsEvent)
    /// Ties the events to the signed-in account, by its id only (no person property).
    func identify(userId: String)
    /// At sign-out: the next events are anonymous again.
    func reset()
}

/// Sends nothing: no key configured, previews, or a store built without analytics.
struct NoAnalyticsClient: AnalyticsClient {
    func capture(_ event: AnalyticsEvent) {}
    func identify(userId: String) {}
    func reset() {}
}
