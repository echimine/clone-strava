import SwiftUI

/// The Paywall (ADR-035 §6): loads the offering through the port, then hands it to the variant
/// its `layout` names. Without offers the store skips it, so only a short loading shows.
struct PaywallView: View {
    @State private var store: PaywallStore
    /// The athlete's first name, on variant C's leaderboard.
    let firstName: String

    init(store: PaywallStore, firstName: String) {
        _store = State(initialValue: store)
        self.firstName = firstName
    }

    var body: some View {
        ZStack {
            if let offering = store.offering, let selected = store.selected {
                layout(PaywallContent(store: store, offering: offering, selected: selected))
                    .transition(.opacity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(.systemBackground))
        .animation(.easeOut(duration: 0.3), value: store.offering)
        .sensoryFeedback(.selection, trigger: store.selected)
        .toast($store.message)
        .task { await store.load() }
    }

    @ViewBuilder
    private func layout(_ content: PaywallContent) -> some View {
        switch content.offering.layout {
        case .a: PaywallLayoutA(content: content)
        case .b: PaywallLayoutB(content: content)
        case .c: PaywallLayoutC(content: content, firstName: firstName)
        }
    }
}

/// What a layout draws and the actions it triggers: the layouts only lay it out. Not the
/// analytics `AnalyticsEvent.PaywallVariant` (A, B, C), which `offering.layout` names.
@MainActor
struct PaywallContent {
    let store: PaywallStore
    let offering: PaywallOffering
    let selected: SubscriptionOffer

    var trialDays: Int { selected.trialDays ?? 0 }

    func select(_ offer: SubscriptionOffer) {
        withAnimation(.snappy(duration: 0.25)) { store.select(offer) }
    }

    func startTrial() {
        Task { await store.startTrial() }
    }

    func skip() {
        store.skip()
    }
}

/// Renewal terms and "Conditions d'utilisation · Confidentialité · Restaurer les achats" under
/// the button (App Store 3.1.2); the legal texts open in their sheet (ADR-035 §9).
struct PaywallFooter: View {
    let content: PaywallContent

    @State private var opened: LegalDocument?

    var body: some View {
        VStack(spacing: 12) {
            Text(PaywallCopy.renewalTerms(content.selected))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Button("Conditions d'utilisation") { opened = .termsOfUse }
                Text("·").accessibilityHidden(true)
                Button("Confidentialité") { opened = .privacyPolicy }
                Text("·").accessibilityHidden(true)
                Button("Restaurer les achats") { Task { await content.store.restorePurchases() } }
                    .disabled(content.store.isBusy)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .sheet(item: $opened) { LegalSheet(document: $0) }
    }
}

/// The circled cross of variants A and B: "Passer".
struct PaywallCloseButton: View {
    var size: CGFloat = 44
    var background: Color = Color(.systemBackground)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
                .background(Circle().fill(background).shadow(color: .black.opacity(0.08), radius: 6, y: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Passer")
        .accessibilityIdentifier("paywall.skip")
    }
}

#if DEBUG
/// Previews only: the hard-coded offering in the asked layout.
private struct PreviewSubscriptionService: SubscriptionService {
    let layout: PaywallLayout

    func paywallOffering() async throws -> PaywallOffering {
        let offering = UnwiredSubscriptionService.offering
        return PaywallOffering(offers: offering.offers, recommendedID: offering.recommendedID, layout: layout)
    }

    func startTrial(_ offer: SubscriptionOffer) async -> PurchaseOutcome { .cancelled }
    func restorePurchases() async -> RestoreOutcome { .unavailable }
}

@MainActor
private func paywallPreview(_ layout: PaywallLayout) -> some View {
    PaywallView(store: PaywallStore(service: PreviewSubscriptionService(layout: layout)) {}, firstName: "Ada")
}

#Preview("A · Strava") { paywallPreview(.a) }
#Preview("B · AllTrails") { paywallPreview(.b) }
#Preview("C · Duolingo, carte") { paywallPreview(.c) }
#endif
