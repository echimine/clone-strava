import SwiftUI

/// The Measurement consent of the first launch (ADR-035 §8), over the Welcome: "Accepter" and
/// "Refuser" side by side with the same size and weight, nothing pre-selected, and the Privacy
/// Policy underneath. Present it with `measurementConsentSheet(_:)`: opaque, no swipe to close,
/// no close button.
struct MeasurementConsentSheet: View {
    let store: MeasurementConsentStore

    @State private var isPolicyOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title)
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("Aidez-nous à améliorer Nervo")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 14)
            Text("Avec votre accord, nous mesurons comment l'app est utilisée : écrans vus, boutons touchés. Ni votre nom, ni votre email, ni vos activités ne sont envoyés. Vous pourrez changer d'avis à tout moment dans votre profil, rubrique Confidentialité.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            HStack(spacing: 12) {
                answerButton("Accepter", identifier: "consent.accept") {
                    Task { await store.accept() }
                }
                answerButton("Refuser", identifier: "consent.refuse") {
                    store.refuse()
                }
            }
            .padding(.top, 24)

            Button(LegalDocument.privacyPolicy.title) { isPolicyOpen = true }
                .font(.footnote)
                .underline()
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
                .accessibilityIdentifier("consent.privacyPolicy")
        }
        .padding(24)
        .sheet(isPresented: $isPolicyOpen) { LegalSheet(document: .privacyPolicy) }
    }

    /// Both answers share this look: neither one is the "main" button.
    private func answerButton(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Capsule().fill(Color(.secondarySystemBackground)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

extension View {
    /// The Measurement consent sheet while `store.isAsking`, sized to its content.
    func measurementConsentSheet(_ store: MeasurementConsentStore) -> some View {
        modifier(MeasurementConsentPresenter(store: store))
    }
}

private struct MeasurementConsentPresenter: ViewModifier {
    let store: MeasurementConsentStore

    @State private var height: CGFloat = 380

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(get: { store.isAsking }, set: { _ in })) {
            MeasurementConsentSheet(store: store)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { height = $0 }
                .presentationDetents([.height(height)])
                .presentationDragIndicator(.hidden)
                .presentationBackground(Color(.systemBackground))
                .interactiveDismissDisabled()
        }
    }
}

#if DEBUG
#Preview {
    Color.orange
        .measurementConsentSheet({
            let store = MeasurementConsentStore(
                preferences: PreviewConsentPreferences(),
                analytics: NoAnalyticsClient(),
                signedInUserID: { nil },
                sleep: { _ in }
            )
            Task { await store.askIfNeeded() }
            return store
        }())
}

private struct PreviewConsentPreferences: MeasurementConsentPreferences {
    var consent: MeasurementConsent? { nil }
    func remember(_ consent: MeasurementConsent) {}
}
#endif
