import Foundation
import PostHog

/// `AnalyticsClient` over PostHog Cloud EU (ADR-015). Only this file imports the SDK.
///
/// The SDK starts **opted out** unless the person accepted the Measurement consent (ADR-035 §8):
/// captures are dropped and nothing leaves the phone until `optIn()`. Screen autocapture, element
/// autocapture, surveys and session replay are off (maps show personal places); app lifecycle
/// events are on, for when consent is given.
final class PostHogAnalyticsClient: AnalyticsClient, @unchecked Sendable {
    /// PostHog Cloud EU ingestion host: data stays in the European Union.
    static let host = "https://eu.i.posthog.com"

    /// The SDK is thread-safe; this instance is never shared through `PostHogSDK.shared`.
    private let sdk: PostHogSDK

    private init(sdk: PostHogSDK) {
        self.sdk = sdk
    }

    /// A client set up with `configuration(projectToken:isOptedIn:)`, or `nil` without a project
    /// token (local builds without `Secrets.xcconfig`).
    /// - Parameter isOptedIn: the stored Measurement consent is "Accepter".
    static func make(projectToken: String, isOptedIn: Bool) -> PostHogAnalyticsClient? {
        let token = projectToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }
        return PostHogAnalyticsClient(sdk: PostHogSDK.with(configuration(projectToken: token, isOptedIn: isOptedIn)))
    }

    static func configuration(projectToken: String, isOptedIn: Bool) -> PostHogConfig {
        let config = PostHogConfig(projectToken: projectToken, host: host)
        // The app's stored choice is the truth: it is set again at each launch.
        config.optOut = !isOptedIn
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

    func optIn() {
        sdk.optIn()
    }

    func optOut() {
        sdk.optOut()
    }

    /// Ignored by the SDK while opted out: re-enabling identifies again (ADR-035 §8).
    func identify(userId: String) {
        sdk.identify(userId)
    }

    func reset() {
        sdk.reset()
    }
}
