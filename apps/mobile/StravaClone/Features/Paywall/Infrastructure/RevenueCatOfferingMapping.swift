import Foundation

/// The part of a RevenueCat offering the Paywall reads, without the SDK's types, so the mapping
/// is tested alone. `RevenueCatSubscriptionService` fills it from the current offering.
struct RevenueCatOfferingSnapshot: Equatable, Sendable {
    struct Product: Equatable, Sendable {
        enum Unit: Sendable {
            case day, week, month, year
        }

        let id: String
        let price: Decimal
        let currencyCode: String?
        /// `nil` for a product that is not a subscription.
        let period: (value: Int, unit: Unit)?
        /// The free trial of the introductory offer, if any.
        let freeTrial: (value: Int, unit: Unit)?

        static func == (lhs: Product, rhs: Product) -> Bool {
            lhs.id == rhs.id && lhs.price == rhs.price && lhs.currencyCode == rhs.currencyCode
                && lhs.period?.value == rhs.period?.value && lhs.period?.unit == rhs.period?.unit
                && lhs.freeTrial?.value == rhs.freeTrial?.value && lhs.freeTrial?.unit == rhs.freeTrial?.unit
        }
    }

    let products: [Product]
    /// The offering's metadata (ADR-014): `layout` (`A`, `B` or `C`) and `recommended` (a product
    /// id). Each RevenueCat Experiments group serves an offering with its own metadata (ADR-016).
    let metadata: [String: String]
}

enum RevenueCatOfferingMapping {
    struct NoSubscription: Error {}

    /// Only monthly and yearly subscriptions are offered, yearly first. Without `recommended`
    /// metadata (or with an unknown id), the yearly offer is pre-selected.
    static func offering(from snapshot: RevenueCatOfferingSnapshot) throws -> PaywallOffering {
        let offers = snapshot.products.compactMap(offer(from:))
            .sorted { $0.period == .year && $1.period != .year }
        guard let fallback = offers.first(where: { $0.period == .year }) ?? offers.first else {
            throw NoSubscription()
        }
        let recommended = snapshot.metadata["recommended"].flatMap { id in offers.first { $0.id == id } }
        return PaywallOffering(
            offers: offers,
            recommendedID: (recommended ?? fallback).id,
            layout: PaywallLayout(metadata: snapshot.metadata["layout"])
        )
    }

    private static func offer(from product: RevenueCatOfferingSnapshot.Product) -> SubscriptionOffer? {
        guard let period = product.period, period.value == 1 else { return nil }
        let offerPeriod: SubscriptionOffer.Period
        switch period.unit {
        case .month: offerPeriod = .month
        case .year: offerPeriod = .year
        case .day, .week: return nil
        }
        return SubscriptionOffer(
            id: product.id,
            period: offerPeriod,
            price: product.price,
            currencyCode: product.currencyCode ?? "EUR",
            trialDays: product.freeTrial.map { days(value: $0.value, unit: $0.unit) }
        )
    }

    private static func days(value: Int, unit: RevenueCatOfferingSnapshot.Product.Unit) -> Int {
        switch unit {
        case .day: value
        case .week: value * 7
        case .month: value * 30
        case .year: value * 365
        }
    }
}
