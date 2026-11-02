import SwiftUI

/// Variant `A`, after Strava's paywall (ADR-035 §6): an orange glow, the round cross, and the
/// trial's dotted timeline (today → 2 days before, the reminder → the charge).
struct PaywallLayoutA: View {
    let content: PaywallContent

    private var steps: [(title: String, detail: String)] {
        [
            ("Aujourd'hui", "Débloquez les fonctionnalités Premium, dont les itinéraires sur mesure, les classements complets, l'analyse de vos progrès et plus encore."),
            ("2 jours avant", "Recevez un rappel avant la fin de votre essai."),
            ("Dans \(content.trialDays) jours", "Le montant de l'abonnement est prélevé. Résiliez au moins 24 heures avant."),
        ]
    }

    private var headline: String {
        let offered = content.trialDays == 30 ? "Le premier mois est offert." : "Les \(content.trialDays) premiers jours sont offerts."
        return "Essayez le meilleur de Nervo.\n\(offered)"
    }

    var body: some View {
        ZStack(alignment: .top) {
            RadialGradient(
                colors: [Theme.accent.opacity(0.5), Theme.accent.opacity(0)],
                center: UnitPoint(x: 0.4, y: -0.02), startRadius: 0, endRadius: 230
            )
            .frame(height: 300)
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    PaywallCloseButton(action: content.skip)
                }
                .padding(.horizontal, Theme.spacing)
                .padding(.top, 8)

                ScrollView {
                    VStack(spacing: 30) {
                        Text(headline)
                            .font(.system(size: 26, weight: .bold))
                            .tracking(-0.3)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(steps.indices, id: \.self) { index in
                                step(steps[index], isLast: index == steps.count - 1)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Text(content.selected.priceAfterTrial)
                    .font(.subheadline.weight(.semibold))
                Button("Démarrer l'essai gratuit", action: content.startTrial)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(content.store.isBusy)
                    .accessibilityIdentifier("paywall.startTrial")
                PaywallFooter(content: content)
            }
            .padding(.horizontal, Theme.spacing)
            .padding(.top, 16)
            .padding(.bottom, 6)
            .background(Color(.systemBackground).shadow(color: .black.opacity(0.06), radius: 3, y: -2))
        }
        // A container, so its buttons keep their own identifiers.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("paywall.layout.A")
    }

    private func step(_ step: (title: String, detail: String), isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 26) {
            VStack(spacing: 6) {
                Circle().fill(Theme.accent).frame(width: 9, height: 9).padding(.top, 9)
                if isLast {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Color(.systemGray))
                } else {
                    // The dotted line between two steps.
                    Line()
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [0.1, 10]))
                        .frame(width: 5)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 30)
            VStack(alignment: .leading, spacing: 6) {
                Text(step.title).font(.system(size: 21))
                Text(step.detail)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : 22)
        }
    }
}

/// A vertical line through the middle of its frame.
private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
    }
}
