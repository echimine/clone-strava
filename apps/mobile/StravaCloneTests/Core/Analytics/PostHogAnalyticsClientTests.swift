import Foundation
import PostHog
import Testing
@testable import StravaClone

/// PostHog setup (ADR-015, ADR-035 §8): the SDK starts cut unless the person accepted the
/// Measurement consent; no screen autocapture, no session replay, EU hosting.
struct PostHogAnalyticsClientTests {
    @Test func withoutConsentTheSDKStartsOptedOutWithoutScreenCaptureNorSessionReplay() {
        let config = PostHogAnalyticsClient.configuration(projectToken: "phc_test", isOptedIn: false)

        #expect(config.optOut)
        #expect(!config.captureScreenViews)
        #expect(!config.sessionReplay)
        #expect(!config.captureElementInteractions)
        #expect(!config.surveys)
        #expect(config.captureApplicationLifecycleEvents)
        #expect(config.host.absoluteString == "https://eu.i.posthog.com")
        #expect(config.projectToken == "phc_test")
    }

    @Test func onceAcceptedTheSDKStartsOpenStillWithoutScreenCaptureNorSessionReplay() {
        let config = PostHogAnalyticsClient.configuration(projectToken: "phc_test", isOptedIn: true)

        #expect(!config.optOut)
        #expect(!config.captureScreenViews)
        #expect(!config.sessionReplay)
        #expect(!config.captureElementInteractions)
        #expect(!config.surveys)
    }

    @Test func withoutAKeyNoSDKIsSetUp() {
        #expect(PostHogAnalyticsClient.make(projectToken: "", isOptedIn: true) == nil)
        #expect(PostHogAnalyticsClient.make(projectToken: "  ", isOptedIn: true) == nil)
    }
}
