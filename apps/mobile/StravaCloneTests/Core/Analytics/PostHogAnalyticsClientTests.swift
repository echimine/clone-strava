import Foundation
import PostHog
import Testing
@testable import StravaClone

/// PostHog setup (ADR-015, ADR-030 §10): until a consent screen exists, the SDK starts opted
/// out, so nothing is sent; no screen autocapture, no session replay, EU hosting.
struct PostHogAnalyticsClientTests {
    @Test func theSDKStartsOptedOutWithoutScreenCaptureNorSessionReplay() {
        let config = PostHogAnalyticsClient.configuration(projectToken: "phc_test")

        #expect(config.optOut)
        #expect(!config.captureScreenViews)
        #expect(!config.sessionReplay)
        #expect(!config.captureElementInteractions)
        #expect(!config.surveys)
        #expect(config.captureApplicationLifecycleEvents)
        #expect(config.host.absoluteString == "https://eu.i.posthog.com")
        #expect(config.projectToken == "phc_test")
    }

    @Test func withoutAKeyNoSDKIsSetUp() {
        #expect(PostHogAnalyticsClient.make(projectToken: "") == nil)
        #expect(PostHogAnalyticsClient.make(projectToken: "  ") == nil)
    }
}
