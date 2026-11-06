import Testing
@testable import StravaClone

/// Where creating a Segment opens (ADR-039 §15), Premium only (ADR-039 §9, amended 2026-11-06).
@MainActor
struct SegmentCreationFlowTests {
    @Test func premiumOpensTheCreation() {
        let flow = SegmentCreationFlow(isOnline: { true }, isPremium: { true })

        flow.start(from: .mySegments)

        #expect(flow.isPresented)
        #expect(flow.entry == .mySegments)
        #expect(!flow.isPaywallPresented)
    }

    @Test func withoutPremiumOpensThePaywall() {
        let flow = SegmentCreationFlow(isOnline: { true }, isPremium: { false })

        flow.start(from: .mapTab)

        #expect(flow.isPaywallPresented)
        #expect(!flow.isPresented)
    }

    @Test func offlineSaysConnectionRequiredFirst() {
        let flow = SegmentCreationFlow(isOnline: { false }, isPremium: { false })

        flow.start(from: .mapTab)

        #expect(flow.toast == SegmentMessages.connectionRequired)
        #expect(!flow.isPaywallPresented)
        #expect(!flow.isPresented)
    }
}
