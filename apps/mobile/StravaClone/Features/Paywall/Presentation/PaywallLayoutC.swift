import SwiftUI

/// Variant `C`, the default (ADR-035 §6): the structure of Duolingo's paywall (a big visual, the
/// free trial highlighted in the title, "Essayer pour 0,00 €" / "Non merci") in Nervo's look,
/// over a real ride on the Outdoors map with what Premium shows about it.
struct PaywallLayoutC: View {
    let content: PaywallContent
    let firstName: String

    var body: some View {
        VStack(spacing: 0) {
            PaywallMapHero(firstName: firstName)
                .frame(height: 470)
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [Color(.systemBackground).opacity(0), Color(.systemBackground)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 36)
                }

            VStack(spacing: 10) {
                Text("Allez plus loin avec \(Text("\(content.trialDays) jours gratuits").foregroundStyle(Theme.accent)) de Premium")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.4)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Classements complets, itinéraires sur mesure, analyse de vos progrès et plus encore.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 12)

            VStack(spacing: 12) {
                Label("Nous vous rappellerons 2 jours avant la fin de votre essai", systemImage: "bell.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                // What is paid after the trial, readable outside the small print (App Store 3.1.2).
                Text(content.selected.priceAfterTrial)
                    .font(.subheadline.weight(.semibold))
                Button("Essayer pour \(content.selected.zeroPrice)", action: content.startTrial)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(content.store.isBusy)
                    .accessibilityIdentifier("paywall.startTrial")
                Button("Non merci", action: content.skip)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 32)
                    .accessibilityIdentifier("paywall.skip")
                PaywallFooter(content: content)
            }
            .padding(.horizontal, Theme.spacing)
            .padding(.bottom, 6)
        }
        .ignoresSafeArea(edges: .top)
        // A container, so its buttons keep their own identifiers.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("paywall.layout.C")
    }
}
