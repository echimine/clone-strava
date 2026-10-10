import Foundation

/// Sends product events (ADR-015). Features depend on this port only, never on the SDK:
/// PostHog in the app (`PostHogAnalyticsClient`), a fake in tests.
protocol AnalyticsClient: Sendable {
    func capture(_ event: AnalyticsEvent)
}

/// Sends nothing: no key configured, previews, or a store built without analytics.
struct NoAnalyticsClient: AnalyticsClient {
    func capture(_ event: AnalyticsEvent) {}
}
