import Foundation
import Observation

/// The Paywall (ADR-035 §6), shown once right after the sign-in that ends the Onboarding. It only
/// knows the `SubscriptionService` port. Nothing is sold yet: "Démarrer l'essai" and "Passer" /
/// "Non merci" continue the flow, and no Premium is granted.
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
    @ObservationIgnored private let finish: @MainActor () -> Void

    init(service: any SubscriptionService, finish: @escaping @MainActor () -> Void) {
        self.service = service
        self.finish = finish
    }

    var layout: PaywallLayout? { offering?.layout }

    /// Offers that cannot be loaded skip the Paywall rather than block the end of the flow.
    func load() async {
        do {
            let offering = try await service.paywallOffering()
            self.offering = offering
            selected = offering.recommended
        } catch {
            finish()
        }
    }

    func select(_ offer: SubscriptionOffer) {
        selected = offer
    }

    func startTrial() async {
        guard let selected, !isBusy else { return }
        isBusy = true
        let outcome = await service.startTrial(selected)
        isBusy = false
        switch outcome {
        case .subscribed, .unavailable: finish()
        case .cancelled: break
        }
    }

    /// "Passer" / "Non merci".
    func skip() {
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
        case .unavailable: message = "Restaurer les achats : non branché pour l'instant."
        }
    }
}
