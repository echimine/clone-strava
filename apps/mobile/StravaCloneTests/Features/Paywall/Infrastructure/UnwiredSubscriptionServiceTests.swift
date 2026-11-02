import Foundation
import Testing
@testable import StravaClone

/// The adapter used until RevenueCat is wired (ADR-035 §6): hard-coded offers, layout `C`,
/// nothing sold.
struct UnwiredSubscriptionServiceTests {
    private let service = UnwiredSubscriptionService()

    @Test func offersAYearlyPreSelectedAndAMonthlyBothWithThirtyFreeDays() async throws {
        let offering = try await service.paywallOffering()

        #expect(offering.offers.map(\.period) == [.year, .month])
        #expect(offering.offers.map(\.price) == [Decimal(string: "59.99")!, Decimal(string: "9.99")!])
        #expect(offering.offers.allSatisfy { $0.currencyCode == "EUR" && $0.trialDays == 30 })
        #expect(offering.recommended?.period == .year)
    }

    @Test func drawsTheDefaultLayout() async throws {
        #expect(try await service.paywallOffering().layout == .c)
    }

    @Test func noPurchaseNorRestoreIsWired() async throws {
        let offer = try #require(try await service.paywallOffering().recommended)

        #expect(await service.startTrial(offer) == .unavailable)
        #expect(await service.restorePurchases() == .unavailable)
    }
}
