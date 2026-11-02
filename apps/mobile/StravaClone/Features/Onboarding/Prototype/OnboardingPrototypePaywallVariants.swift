#if DEBUG
import SwiftUI

// PROTOTYPE — throwaway (see OnboardingPrototypePaywall.swift). Three known paywalls, reproduced
// from Mobbin captures with Nervo's copy, fed by the same `ProtoPaywallContext`:
// A « Strava »: https://mobbin.com/screens/94178124-98a0-4282-88c4-eb65c8e5de01
// B « AllTrails »: https://mobbin.com/screens/0e508882-f772-497d-959e-d51095983ef1
// C « Duolingo » (structure only, in Nervo's look): OnboardingPrototypePaywallMap.swift

// MARK: - A « Strava »

struct ProtoPaywallA: View {
    let c: ProtoPaywallContext

    private var trialDays: Int { c.selected.trialDays ?? 0 }

    private var steps: [(title: String, detail: String)] {
        [
            ("Aujourd'hui", "Débloquez les fonctionnalités Premium, dont les itinéraires sur mesure, les classements complets, l'analyse de vos progrès et plus encore."),
            ("2 jours avant", "Recevez un rappel avant la fin de votre essai."),
            ("Dans \(trialDays) jours", "Le montant de l'abonnement est prélevé. Résiliez au moins 24 heures avant."),
        ]
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()
            // The orange glow bleeding from the top-left corner.
            RadialGradient(colors: [Theme.accent.opacity(0.5), Theme.accent.opacity(0)],
                           center: UnitPoint(x: 0.4, y: -0.02), startRadius: 0, endRadius: 230)
                .frame(height: 300)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: c.skip) {
                        Image(systemName: "xmark").font(.system(size: 20, weight: .regular)).foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color(.systemBackground)).shadow(color: .black.opacity(0.08), radius: 6, y: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Passer")
                }
                .padding(.horizontal, Theme.spacing).padding(.top, 8)

                ScrollView {
                    VStack(spacing: 30) {
                        Text("Essayez le meilleur de Nervo.\n\(trialDays == 30 ? "Le premier mois" : "Les \(trialDays) premiers jours") est offert.")
                            .font(.system(size: 26, weight: .bold)).tracking(-0.3)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(steps.indices, id: \.self) { index in
                                step(steps[index], isLast: index == steps.count - 1)
                            }
                        }
                    }
                    .padding(.horizontal, 24).padding(.top, 4).padding(.bottom, 24)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button(action: c.startTrial) {
                    Text(c.isBusy ? "…" : "Démarrer l'essai gratuit").font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Capsule().fill(Theme.accent))
                }
                .buttonStyle(ProtoPressStyle())
                .disabled(c.isBusy)
                ProtoPaywallLegal(c: c)
            }
            .padding(.horizontal, Theme.spacing).padding(.top, 20).padding(.bottom, 6)
            .background(Color(.systemBackground).shadow(color: .black.opacity(0.06), radius: 3, y: -2))
        }
    }

    private func step(_ step: (title: String, detail: String), isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 26) {
            VStack(spacing: 6) {
                Circle().fill(Theme.accent).frame(width: 9, height: 9).padding(.top, 9)
                if isLast {
                    Image(systemName: "arrow.down").font(.system(size: 30, weight: .bold)).foregroundStyle(Color(.systemGray))
                } else {
                    Capsule().fill(Theme.accent).frame(width: 5).frame(maxHeight: .infinity)
                }
            }
            .frame(width: 30)
            VStack(alignment: .leading, spacing: 6) {
                Text(step.title).font(.system(size: 21))
                Text(step.detail).font(.system(size: 16)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : 22)
        }
    }
}

// MARK: - B « AllTrails »

struct ProtoPaywallB: View {
    let c: ProtoPaywallContext

    private var ink: Color { Color(red: 0.09, green: 0.12, blue: 0.10) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Button(action: c.skip) {
                        Image(systemName: "xmark").font(.system(size: 17, weight: .medium)).foregroundStyle(.primary)
                            .frame(width: 44, height: 44).background(Circle().fill(Color(.systemGray6)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Passer")

                    Text(c.selected.trialDays == 30 ? "Votre premier mois est offert" : "Passez à Premium")
                        .font(.system(size: 31, weight: .medium)).tracking(-0.6)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 16)

                    HStack {
                        Text("Choisissez votre formule").font(.subheadline.weight(.medium))
                        Spacer()
                        Button("Comparer") { withAnimation { proxy.scrollTo("table", anchor: .top) } }
                            .font(.subheadline.weight(.medium)).underline().foregroundStyle(.primary)
                    }
                    .padding(.top, 26)

                    VStack(spacing: 14) {
                        ForEach(c.offering.offers) { offer in planCard(offer) }
                    }
                    .padding(.top, 12)

                    table.id("table").padding(.top, 34)

                    ProtoPaywallLegal(c: c).padding(.top, 28)
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 130)
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 10) {
                Button(action: c.startTrial) {
                    Text(c.isBusy ? "…" : "Démarrer l'essai gratuit").font(.system(size: 18, weight: .medium)).foregroundStyle(.white)
                        .padding(.horizontal, 30).frame(minHeight: 56)
                        .background(Capsule().fill(ink))
                }
                .buttonStyle(ProtoPressStyle())
                .disabled(c.isBusy)
                Text("Sans engagement").font(.subheadline)
            }
            .padding(.top, 30).padding(.bottom, 6)
            .frame(maxWidth: .infinity)
            .background(LinearGradient(colors: [Color(.systemBackground).opacity(0), Color(.systemBackground)],
                                       startPoint: .top, endPoint: .init(x: 0.5, y: 0.35)))
        }
    }

    private func planCard(_ offer: ProtoSubscriptionOffer) -> some View {
        let isSelected = offer == c.selected
        return Button { c.select(offer) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: offer.period == .year ? "sparkle" : "circle.hexagongrid.fill")
                        .font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.accent)
                    Text(offer.title).font(.system(size: 22, weight: .medium))
                    Spacer()
                    if offer.period == .year, let savings = c.offering.yearlySavingsPercent {
                        Text("−\(savings) % sur l'année").font(.caption.weight(.medium))
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.accent.opacity(0.12)))
                    }
                }
                Text(offer.period == .year ? "Tout Premium, au meilleur prix" : "Tout Premium, sans engagement")
                    .font(.system(size: 17)).foregroundStyle(.secondary)
                (Text(offer.formattedPrice).fontWeight(.semibold) + Text("/\(offer.shortPeriod)")
                    + Text(offer.period == .year ? " (soit \(offer.monthlyPrice)/mois)" : ""))
                    .font(.subheadline)

                if isSelected, let days = offer.trialDays {
                    VStack(alignment: .leading, spacing: 0) {
                        timelineRow("lock.open", Text("Aujourd'hui :").fontWeight(.semibold) + Text(" début de votre essai gratuit"), isLast: false)
                        timelineRow("bell", Text("Jour \(days - 2) :").fontWeight(.semibold) + Text(" rappel avant la fin de l'essai"), isLast: false)
                        timelineRow("star", Text("Jour \(days) :").fontWeight(.semibold) + Text(" prélèvement de \(offer.formattedPrice)/\(offer.shortPeriod)"), isLast: true)
                    }
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? Theme.accent.opacity(0.05) : Color(.systemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isSelected ? ink : Color(.systemGray4), lineWidth: isSelected ? 2.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func timelineRow(_ symbol: String, _ text: Text, isLast: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Theme.accent.opacity(0.12)))
            text.font(.subheadline)
        }
        .padding(.bottom, isLast ? 0 : 10)
        .background(alignment: .leading) {
            if !isLast {
                Rectangle().fill(Theme.accent.opacity(0.12)).frame(width: 6).padding(.leading, 12).padding(.top, 26)
            }
        }
    }

    /// Premium-only rows first, shared rows dimmed (as AllTrails does).
    private var table: some View {
        let rows = ProtoPaywallCopy.comparison.filter { !$0.free } + ProtoPaywallCopy.comparison.filter(\.free)
        return VStack(spacing: 0) {
            HStack {
                Text("Ce que vous obtenez").frame(maxWidth: .infinity, alignment: .leading)
                Text("Gratuit").frame(width: 62)
                Text("Premium").foregroundStyle(.primary).frame(width: 70)
            }
            .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            .padding(.vertical, 14)
            Divider()
            ForEach(rows, id: \.feature) { row in
                HStack {
                    Text(row.feature).foregroundStyle(row.free ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "checkmark").opacity(row.free ? 1 : 0).frame(width: 62)
                    Image(systemName: "checkmark").frame(width: 70)
                }
                .font(.subheadline)
                .padding(.vertical, 14)
                Divider()
            }
        }
        .background(alignment: .trailing) {
            Rectangle().fill(Theme.accent.opacity(0.08)).frame(width: 70)
        }
    }
}
#endif
