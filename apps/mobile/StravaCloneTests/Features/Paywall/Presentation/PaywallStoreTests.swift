import Foundation
import Testing
@testable import StravaClone

/// The Paywall screen (ADR-035 §6), through the `SubscriptionService` port only: the offering's
/// `layout` picks the variant; nothing is sold yet, so every way out continues the flow.
@MainActor
struct PaywallStoreTests {
    private let service = FakeSubscriptionService()
    private let finished = Locked(0)

    private func makeStore() -> PaywallStore {
        PaywallStore(service: service) { [finished] in finished.value += 1 }
    }

    @Test(arguments: PaywallLayout.allCases)
    func eachLayoutShowsItsVariant(layout: PaywallLayout) async {
        service.offering = .sample(layout: layout)
        let store = makeStore()

        await store.load()

        #expect(store.layout == layout)
    }

    @Test func offersThatCannotBeLoadedSkipThePaywall() async {
        service.offering = nil
        let store = makeStore()

        await store.load()

        #expect(store.layout == nil)
        #expect(finished.value == 1)
    }

    @Test func theRecommendedOfferIsPreSelected() async {
        let store = makeStore()

        await store.load()

        #expect(store.selected == .yearly)
    }

    /// Unwired: the button continues the flow and no Premium is granted.
    @Test func startingTheTrialContinuesWithoutPremium() async {
        service.trialOutcome = .unavailable
        let store = makeStore()
        await store.load()
        store.select(.monthly)

        await store.startTrial()

        #expect(service.trialsStarted == [.monthly])
        #expect(finished.value == 1)
    }

    @Test func skippingContinues() async {
        let store = makeStore()
        await store.load()

        store.skip()

        #expect(service.trialsStarted.isEmpty)
        #expect(finished.value == 1)
    }

    @Test func restoringPurchasesSaysItIsNotWiredAndStays() async {
        service.restoreOutcome = .unavailable
        let store = makeStore()
        await store.load()

        await store.restorePurchases()

        #expect(store.message == "Restaurer les achats : non branché pour l'instant.")
        #expect(finished.value == 0)
    }
}
