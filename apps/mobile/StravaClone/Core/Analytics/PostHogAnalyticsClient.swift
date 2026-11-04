import Foundation
import PostHog

/// `AnalyticsClient` over PostHog Cloud EU (ADR-015). Only this file imports the SDK.
///
/// It always collects: there is no consent to ask (ADR-035 §8, amended). Screen autocapture,
/// element autocapture, surveys and session replay are off (maps show personal places); app
/// lifecycle events are on.
final class PostHogAnalyticsClient: AnalyticsClient, @unchecked Sendable {
    /// PostHog Cloud EU ingestion host: data stays in the European Union.
    static let host = "https://eu.i.posthog.com"

    /// The SDK is thread-safe; this instance is never shared through `PostHogSDK.shared`.
    private let sdk: PostHogSDK

    private init(sdk: PostHogSDK) {
        self.sdk = sdk
    }

    /// A client set up with `configuration(projectToken:)`, or `nil` without a project token
    /// (local builds without `Secrets.xcconfig`).
    static func make(projectToken: String) -> PostHogAnalyticsClient? {
        let token = projectToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }
        let sdk = PostHogSDK.with(configuration(projectToken: token))
        // The former Measurement consent's "Refuser" called `optOut()`, which the SDK keeps on
        // disk (`posthog.optOut`) and which outranks `config.optOut` at the next setup: undo it.
        // A no-op when not opted out.
        sdk.optIn()
        return PostHogAnalyticsClient(sdk: sdk)
    }

    static func configuration(projectToken: String) -> PostHogConfig {
        let config = PostHogConfig(projectToken: projectToken, host: host)
        config.optOut = false
        config.captureScreenViews = false
        config.captureApplicationLifecycleEvents = true
        config.captureElementInteractions = false
        config.sessionReplay = false
        config.surveys = false
        return config
    }

    func capture(_ event: AnalyticsEvent) {
        sdk.capture(event.name, properties: event.properties.mapValues(\.plainValue))
    }

    func identify(userId: String) {
        sdk.identify(userId)
    }

    func reset() {
        sdk.reset()
    }
}
