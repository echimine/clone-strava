import SwiftUI

/// Premium in the shell (ADR-014): the status observed while signed in, the Paywall of the home's
/// « S'abonner », and the one that replaces the editor when an athlete without Premium creates an
/// Itinerary or a Segment (ADR-030 §6, ADR-039 §9, amended 2026-11-06).
extension RootView {
    /// The signed-in tabs, with the Premium status and its Paywalls.
    func premium(_ tabs: some View) -> some View {
        tabs
            .task { await premiumStore.observe() }
            // « S'abonner »: the same Paywall as after the Onboarding, as often as tapped.
            .fullScreenCover(isPresented: $isSubscribePaywallPresented) {
                if case .signedIn(let user) = authStore.state {
                    PaywallView(store: makePaywallStore(false) { isSubscribePaywallPresented = false }, firstName: user.firstName)
                }
            }
            .fullScreenCover(isPresented: $itineraryCreation.isPaywallPresented) {
                paywall(.itineraryCreation) { itineraryCreation.isPaywallPresented = false }
            }
            .fullScreenCover(isPresented: $segmentCreation.isPaywallPresented) {
                paywall(.segmentCreation) { segmentCreation.isPaywallPresented = false }
            }
    }

    /// The Onboarding's Paywall, opened from `entry`; any way out calls `close`.
    func paywall(_ entry: AnalyticsEvent.PaywallEntry, close: @escaping @MainActor () -> Void) -> AnyView {
        let firstName = if case .signedIn(let user) = authStore.state { user.firstName } else { "" }
        return AnyView(PaywallView(store: segmentScreens.makePaywallStore(entry, close), firstName: firstName))
    }
}

extension View {
    /// `RootView.premium(_:)` at the end of a modifier chain.
    @MainActor
    func premium(in root: RootView) -> some View {
        root.premium(self)
    }
}
