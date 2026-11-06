import Testing
@testable import StravaClone

/// The `premium` entitlement as the app shows it (ADR-014).
@MainActor
struct PremiumStoreTests {
    private struct Scripted: PremiumStatus {
        let values: [Bool]

        func premiumUpdates() -> AsyncStream<Bool> {
            AsyncStream { continuation in
                values.forEach { continuation.yield($0) }
                continuation.finish()
            }
        }
    }

    @Test func notPremiumUntilTheFirstAnswer() {
        #expect(!PremiumStore(status: Scripted(values: [true])).isPremium)
    }

    @Test func followsEachChangeOfTheEntitlement() async {
        let store = PremiumStore(status: Scripted(values: [false, true]))
        await store.observe()
        #expect(store.isPremium)

        let expired = PremiumStore(status: Scripted(values: [true, false]))
        await expired.observe()
        #expect(!expired.isPremium)
    }

    @Test func neverPremiumWithoutRevenueCat() async {
        let store = PremiumStore(status: NoPremiumStatus())
        await store.observe()
        #expect(!store.isPremium)
    }
}
