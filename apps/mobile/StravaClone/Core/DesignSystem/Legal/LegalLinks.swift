import SwiftUI

/// "Conditions d'utilisation · Politique de confidentialité", each opening its `LegalSheet`
/// (ADR-035 §9). Shared by the account screen, the "Confidentialité" section and the Paywall
/// footer; they style it with `.font` / `.foregroundStyle`, which it inherits.
struct LegalLinks: View {
    @State private var opened: LegalDocument?

    var body: some View {
        HStack(spacing: 6) {
            link(.termsOfUse)
            Text("·").accessibilityHidden(true)
            link(.privacyPolicy)
        }
        .buttonStyle(.plain)
        .sheet(item: $opened) { LegalSheet(document: $0) }
    }

    private func link(_ document: LegalDocument) -> some View {
        Button(document.title) { opened = document }
            .underline()
            .accessibilityIdentifier("legalLink.\(document.rawValue)")
    }
}

#Preview {
    LegalLinks()
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
}
