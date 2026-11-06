import Foundation
import Observation

/// The Paywall (ADR-035 §6), shown once right after the sign-in that ends the Onboarding. It only
/// knows the `SubscriptionService` port. A purchase that goes through, or "Passer" / "Non merci",
/// continues the flow; a cancelled one stays; a failed one stays with a message. Unwired (no
/// RevenueCat key), "Démarrer l'essai" continues without granting Premium.
///
/// It is measured, never driven, by PostHog (ADR-016, ADR-035 §8): `paywall_viewed`,
/// `paywall_skipped`, `paywall_trial_tapped` and `paywall_dismissed`.
@Observable
@MainActor
final class PaywallStore {
    private(set) var offering: PaywallOffering?
    /// The offer the button buys; the recommended one until another is picked.
    private(set) var selected: SubscriptionOffer?
    /// While a purchase or a restore is in flight.
    private(set) var isBusy = false
    /// A short message over the Paywall (a toast), cleared by the view.
    var message: String?

    @ObservationIgnored private let service: any SubscriptionService
    @ObservationIgnored private let analytics: any AnalyticsClient
    /// The sign-in before it created the account.
    @ObservationIgnored private let isNewAccount: Bool
    /// Where it opened: the Onboarding, or a lock of a Segment's Leaderboard (ADR-039 §9).
    @ObservationIgnored private let entry: AnalyticsEvent.PaywallEntry
    @ObservationIgnored private let finish: @MainActor () -> Void

    init(
        service: any SubscriptionService,
        analytics: any AnalyticsClient = NoAnalyticsClient(),
        isNewAccount: Bool = false,
        entry: AnalyticsEvent.PaywallEntry = .onboarding,
        finish: @escaping @MainActor () -> Void
    ) {
        self.service = service
        self.analytics = analytics
        self.isNewAccount = isNewAccount
        self.entry = entry
        self.finish = finish
    }

    var layout: PaywallLayout? { offering?.layout }

    /// Offers that cannot be loaded skip the Paywall rather than block the end of the flow.
    func load() async {
        do {
            let offering = try await service.paywallOffering()
            self.offering = offering
            selected = offering.recommended
            analytics.capture(.paywallViewed(layout: .init(offering.layout), isNewAccount: isNewAccount, entry: entry))
        } catch {
            analytics.capture(.paywallSkipped(reason: .offersUnavailable))
            finish()
        }
    }

    func select(_ offer: SubscriptionOffer) {
        selected = offer
    }

    func startTrial() async {
        guard let selected, let layout, !isBusy else { return }
        analytics.capture(.paywallTrialTapped(layout: .init(layout), period: .init(selected.period)))
        isBusy = true
        let outcome = await service.startTrial(selected)
        isBusy = false
        switch outcome {
        case .subscribed, .unavailable: finish()
        case .cancelled: break
        case .failed: message = "L'achat n'a pas abouti. Réessayez."
        }
    }

    /// "Passer" / "Non merci".
    func skip() {
        if let layout {
            analytics.capture(.paywallDismissed(layout: .init(layout)))
        }
        finish()
    }

    func restorePurchases() async {
        guard !isBusy else { return }
        isBusy = true
        let outcome = await service.restorePurchases()
        isBusy = false
        switch outcome {
        case .restored: finish()
        case .nothingToRestore: message = "Aucun achat à restaurer."
        case .failed: message = "Impossible de restaurer les achats. Réessayez."
        case .unavailable: message = "Restaurer les achats : non branché pour l'instant."
        }
    }
}

private extension AnalyticsEvent.PaywallVariant {
    init(_ layout: PaywallLayout) {
        switch layout {
        case .a: self = .a
        case .b: self = .b
        case .c: self = .c
        }
    }
}

private extension AnalyticsEvent.TrialPeriod {
    init(_ period: SubscriptionOffer.Period) {
        switch period {
        case .year: self = .year
        case .month: self = .month
        }
    }
}
