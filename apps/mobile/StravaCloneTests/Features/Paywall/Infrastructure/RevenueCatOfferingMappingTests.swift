import Foundation
import Testing
@testable import StravaClone

/// RevenueCat's current offering onto the Paywall's types (ADR-014): monthly and yearly
/// subscriptions only, yearly first, the `layout` and `recommended` metadata of the
/// Experiment's group (ADR-016).
struct RevenueCatOfferingMappingTests {
    private typealias Product = RevenueCatOfferingSnapshot.Product

    private let yearly = Product(
        id: "nervo_premium_yearly", price: Decimal(string: "59.99")!, currencyCode: "EUR",
        period: (1, .year), freeTrial: (1, .month)
    )
    private let monthly = Product(
        id: "nervo_premium_monthly", price: Decimal(string: "9.99")!, currencyCode: "EUR",
        period: (1, .month), freeTrial: (30, .day)
    )

    @Test func mapsSubscriptionsYearlyFirstWithTheirTrial() throws {
        let offering = try RevenueCatOfferingMapping.offering(
            from: .init(products: [monthly, yearly], metadata: [:])
        )

        #expect(offering.offers == [
            SubscriptionOffer(id: "nervo_premium_yearly", period: .year, price: Decimal(string: "59.99")!, currencyCode: "EUR", trialDays: 30),
            SubscriptionOffer(id: "nervo_premium_monthly", period: .month, price: Decimal(string: "9.99")!, currencyCode: "EUR", trialDays: 30),
        ])
    }

    @Test func withoutMetadataTheYearlyOfferIsRecommendedAndTheLayoutIsC() throws {
        let offering = try RevenueCatOfferingMapping.offering(
            from: .init(products: [monthly, yearly], metadata: [:])
        )

        #expect(offering.recommendedID == "nervo_premium_yearly")
        #expect(offering.layout == .c)
    }

    @Test(arguments: PaywallLayout.allCases)
    func theLayoutMetadataPicksTheVariant(layout: PaywallLayout) throws {
        let offering = try RevenueCatOfferingMapping.offering(
            from: .init(products: [yearly, monthly], metadata: ["layout": layout.rawValue])
        )

        #expect(offering.layout == layout)
    }

    @Test func theRecommendedMetadataPicksTheOffer() throws {
        let offering = try RevenueCatOfferingMapping.offering(
            from: .init(products: [yearly, monthly], metadata: ["recommended": "nervo_premium_monthly"])
        )

        #expect(offering.recommendedID == "nervo_premium_monthly")
    }

    @Test func anUnknownRecommendedIdFallsBackToYearly() throws {
        let offering = try RevenueCatOfferingMapping.offering(
            from: .init(products: [monthly, yearly], metadata: ["recommended": "gone"])
        )

        #expect(offering.recommendedID == "nervo_premium_yearly")
    }

    @Test func otherPeriodsAndNonSubscriptionsAreLeftOut() throws {
        let weekly = Product(id: "weekly", price: 1, currencyCode: "EUR", period: (1, .week), freeTrial: nil)
        let lifetime = Product(id: "lifetime", price: 99, currencyCode: "EUR", period: nil, freeTrial: nil)

        let offering = try RevenueCatOfferingMapping.offering(
            from: .init(products: [weekly, lifetime, monthly], metadata: [:])
        )

        #expect(offering.offers.map(\.id) == ["nervo_premium_monthly"])
        #expect(offering.offers.first?.trialDays == 30)
    }

    @Test func anOfferingWithoutSubscriptionCannotBeShown() {
        #expect(throws: RevenueCatOfferingMapping.NoSubscription.self) {
            try RevenueCatOfferingMapping.offering(from: .init(products: [], metadata: [:]))
        }
    }
}
