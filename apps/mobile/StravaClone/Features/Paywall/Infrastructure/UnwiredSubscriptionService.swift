import Foundation

/// The `SubscriptionService` until RevenueCat is wired (ADR-035 §6): hard-coded offers (30 free
/// days, then €59.99/year pre-selected or €9.99/month), the default layout, and nothing sold.
/// Never fails, so the Paywall always shows.
struct UnwiredSubscriptionService: SubscriptionService {
    static let offering = PaywallOffering(
        offers: [
            SubscriptionOffer(
                id: "nervo_premium_yearly", period: .year, price: Decimal(string: "59.99")!, currencyCode: "EUR", trialDays: 30
            ),
            SubscriptionOffer(
                id: "nervo_premium_monthly", period: .month, price: Decimal(string: "9.99")!, currencyCode: "EUR", trialDays: 30
            ),
        ],
        recommendedID: "nervo_premium_yearly",
        layout: PaywallLayout(metadata: nil)
    )

    func paywallOffering() async throws -> PaywallOffering {
        Self.offering
    }

    func startTrial(_ offer: SubscriptionOffer) async -> PurchaseOutcome {
        .unavailable
    }

    func restorePurchases() async -> RestoreOutcome {
        .unavailable
    }
}
