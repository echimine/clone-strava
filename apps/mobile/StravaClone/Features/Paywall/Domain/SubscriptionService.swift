import Foundation

/// What the Paywall knows about subscriptions (ADR-014, amended by ADR-035 §6). The screen only
/// talks to this port: today `UnwiredSubscriptionService` answers with hard-coded offers; later a
/// RevenueCat adapter in `Infrastructure/` maps the current offering (localised prices, trial,
/// `layout` metadata) onto the same types, and the screen does not change.
protocol SubscriptionService: Sendable {
    /// The current offering. Throws when it cannot be loaded (offline, outage): the Paywall is
    /// then skipped.
    func paywallOffering() async throws -> PaywallOffering
    /// "Démarrer l'essai" on `offer`.
    func startTrial(_ offer: SubscriptionOffer) async -> PurchaseOutcome
    /// "Restaurer les achats", required by the App Store.
    func restorePurchases() async -> RestoreOutcome
}

/// One subscription the Paywall offers (a RevenueCat package, tomorrow).
struct SubscriptionOffer: Identifiable, Hashable, Sendable {
    enum Period: Sendable {
        case month, year
    }

    /// The App Store product id.
    let id: String
    let period: Period
    let price: Decimal
    let currencyCode: String
    /// `nil`: no free trial on this offer.
    let trialDays: Int?
}

/// What the Paywall shows: the offers, the one pre-selected, and which variant draws them.
struct PaywallOffering: Equatable, Sendable {
    let offers: [SubscriptionOffer]
    /// Pre-selected and badged.
    let recommendedID: String
    /// The offering's `layout` metadata, set per RevenueCat Experiments group (ADR-016).
    let layout: PaywallLayout

    var recommended: SubscriptionOffer? {
        offers.first { $0.id == recommendedID } ?? offers.first
    }
}

/// The three Paywall variants, all kept for A/B testing (ADR-035 §6).
enum PaywallLayout: String, CaseIterable, Sendable {
    /// Strava: the trial's timeline.
    case a = "A"
    /// AllTrails: offer cards and a Free/Premium table.
    case b = "B"
    /// Duolingo with a real map: the default.
    case c = "C"

    /// From the offering's `layout` metadata; missing or unknown gives the default, `C`.
    init(metadata: String?) {
        self = metadata.flatMap(Self.init(rawValue:)) ?? .c
    }
}

enum PurchaseOutcome: Sendable {
    case subscribed, cancelled
    /// Purchases are not wired yet: no Premium is granted.
    case unavailable
}

enum RestoreOutcome: Sendable {
    case restored, nothingToRestore
    /// Purchases are not wired yet.
    case unavailable
}
