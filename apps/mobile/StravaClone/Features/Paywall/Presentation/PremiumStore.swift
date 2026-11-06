import Foundation
import Observation

/// Whether the signed-in athlete is Premium, for what the app shows (ADR-014): the home header's
/// Nervo logo instead of « S'abonner », and the Paywall before creating an Itinerary or a
/// Segment. One for the app, observed while signed in; `false` until the first answer.
@Observable
@MainActor
final class PremiumStore {
    private(set) var isPremium = false

    @ObservationIgnored private let status: any PremiumStatus

    init(status: any PremiumStatus) {
        self.status = status
    }

    /// Runs for the lifetime of the signed-in tabs.
    func observe() async {
        for await isPremium in status.premiumUpdates() {
            self.isPremium = isPremium
        }
    }
}
