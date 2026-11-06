import Foundation
import Testing
@testable import StravaClone

/// The Paywall's part of the getting-started funnel (ADR-035 §8), through `PaywallStore`: what
/// was shown (its `layout`), skipped, tapped or dismissed. PostHog only measures it (ADR-016).
@MainActor
struct PaywallStoreAnalyticsTests {
    private let service = FakeSubscriptionService()
    private let analytics = FakeAnalyticsClient()

    private func makeStore(isNewAccount: Bool = true) -> PaywallStore {
        PaywallStore(service: service, analytics: analytics, isNewAccount: isNewAccount) {}
    }

    @Test(arguments: [
        (PaywallLayout.a, AnalyticsEvent.PaywallVariant.a),
        (.b, .b),
        (.c, .c),
    ])
    func theShownPaywallIsViewedWithItsLayout(layout: PaywallLayout, variant: AnalyticsEvent.PaywallVariant) async {
        service.offering = .sample(layout: layout)

        await makeStore(isNewAccount: false).load()

        #expect(analytics.events == [.paywallViewed(layout: variant, isNewAccount: false, entry: .onboarding)])
        #expect(
            analytics.events.first?.properties
                == ["layout": .string(variant.rawValue), "isNewAccount": false, "entry": "onboarding"]
        )
    }

    /// ADR-039 §9: each lock of a Segment's Leaderboard opens the Paywall in a sheet, named by `entry`.
    @Test(arguments: [AnalyticsEvent.PaywallEntry.segmentLeaderboard, .leaderboardFilter])
    func aPaywallOpenedFromALockIsViewedWithItsEntry(entry: AnalyticsEvent.PaywallEntry) async {
        service.offering = .sample(layout: .a)

        await PaywallStore(service: service, analytics: analytics, entry: entry) {}.load()

        #expect(analytics.events == [.paywallViewed(layout: .a, isNewAccount: false, entry: entry)])
        #expect(analytics.events.first?.properties["entry"] == .string(entry.rawValue))
    }

    @Test func offersThatCannotBeLoadedSkipThePaywallWithoutViewingIt() async {
        service.offering = nil

        await makeStore().load()

        #expect(analytics.events == [.paywallSkipped(reason: .offersUnavailable)])
    }

    @Test func startTheTrialIsTappedWithTheLayoutAndThePeriod() async {
        service.offering = .sample(layout: .b)
        service.trialOutcome = .cancelled
        let store = makeStore()
        await store.load()
        store.select(.monthly)

        await store.startTrial()

        #expect(analytics.events.last == .paywallTrialTapped(layout: .b, period: .month))
    }

    @Test func passerDismissesThePaywall() async {
        let store = makeStore()
        await store.load()

        store.skip()

        #expect(analytics.names == ["paywall_viewed", "paywall_dismissed"])
        #expect(analytics.events.last == .paywallDismissed(layout: .c))
    }
}
