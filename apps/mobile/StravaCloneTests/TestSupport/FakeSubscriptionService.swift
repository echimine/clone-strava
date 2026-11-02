import Foundation
@testable import StravaClone

/// Fake `SubscriptionService` (ADR-025 §3): answers with the offering, outcomes and failure set
/// per test, and records the trials started.
final class FakeSubscriptionService: SubscriptionService, @unchecked Sendable {
    struct Unavailable: Error {}

    /// `nil`: the offering cannot be loaded.
    var offering: PaywallOffering?
    var trialOutcome = PurchaseOutcome.unavailable
    var restoreOutcome = RestoreOutcome.unavailable
    private(set) var trialsStarted: [SubscriptionOffer] = []

    init(offering: PaywallOffering? = .sample(layout: .c)) {
        self.offering = offering
    }

    func paywallOffering() async throws -> PaywallOffering {
        guard let offering else { throw Unavailable() }
        return offering
    }

    func startTrial(_ offer: SubscriptionOffer) async -> PurchaseOutcome {
        trialsStarted.append(offer)
        return trialOutcome
    }

    func restorePurchases() async -> RestoreOutcome {
        restoreOutcome
    }
}

extension SubscriptionOffer {
    static let yearly = SubscriptionOffer(
        id: "yearly", period: .year, price: Decimal(string: "59.99")!, currencyCode: "EUR", trialDays: 30
    )
    static let monthly = SubscriptionOffer(
        id: "monthly", period: .month, price: Decimal(string: "9.99")!, currencyCode: "EUR", trialDays: 30
    )
}

extension PaywallOffering {
    static func sample(layout: PaywallLayout) -> PaywallOffering {
        PaywallOffering(offers: [.yearly, .monthly], recommendedID: "yearly", layout: layout)
    }
}
