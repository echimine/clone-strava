import Foundation
import PostHog

/// `AnalyticsClient` over PostHog Cloud EU (ADR-015). Only this file imports the SDK.
///
/// Until the consent screen exists (out of scope, ADR-030 §10), the SDK starts **opted out**:
/// captures are dropped and nothing leaves the phone. Screen autocapture, element
/// autocapture, surveys and session replay are off (maps show personal places); app
/// lifecycle events are on, for when consent is given.
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
        return PostHogAnalyticsClient(sdk: PostHogSDK.with(configuration(projectToken: token)))
    }

    static func configuration(projectToken: String) -> PostHogConfig {
        let config = PostHogConfig(projectToken: projectToken, host: host)
        config.optOut = true
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
}
