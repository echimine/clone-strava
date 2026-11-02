#if DEBUG
import SwiftUI

// PROTOTYPE — throwaway (see OnboardingPrototypePaywall.swift). Three structurally different
// Paywalls fed by the same `ProtoPaywallContext`:
// A « Avantages »: orange hero, perks list, stacked plan rows, « Passer » under the button (Strava).
// B « Essai expliqué »: trial timeline (today → reminder → first payment), one price, segmented plan.
// C « Gratuit vs Premium »: dark screen, Free / Premium comparison table, plans side by side.

// MARK: - A « Avantages »

struct ProtoPaywallA: View {
    let c: ProtoPaywallContext

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(ProtoPaywallCopy.perks) { perk in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: perk.symbol).font(.body.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 40, height: 40)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Theme.accent.opacity(0.12)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(perk.title).font(.body.weight(.semibold))
                                Text(perk.detail).font(.subheadline).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.spacing).padding(.top, 24)

                VStack(spacing: 10) {
                    ForEach(c.offering.offers) { offer in planRow(offer) }
                }
                .padding(.horizontal, Theme.spacing).padding(.top, 28)

                ProtoPaywallLegal(c: c)
                    .padding(.horizontal, Theme.spacing).padding(.vertical, 24)
            }
        }
        .ignoresSafeArea(edges: .top)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                ProtoPrimaryButton(title: c.isBusy ? "…" : "Démarrer l'essai gratuit", isEnabled: !c.isBusy, action: c.startTrial)
                Button("Passer", action: c.skip)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    .frame(minHeight: 40)
            }
            .padding(.horizontal, Theme.spacing).padding(.top, 10)
            .background(.bar)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                NervoMark().stroke(.white, style: NervoMark.strokeStyle(forSide: 28)).frame(width: 28, height: 28)
                Text("PREMIUM").font(.caption.weight(.heavy)).tracking(1.5)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(.white.opacity(0.22)))
            }
            Text(c.firstName.isEmpty ? "Essayez Nervo Premium" : "\(c.firstName), essayez Nervo Premium")
                .font(.system(size: 30, weight: .bold)).tracking(-0.4)
                .fixedSize(horizontal: false, vertical: true)
            if let days = c.selected.trialDays {
                Text("\(days) jours offerts, sans engagement. Résiliable à tout moment.")
                    .font(.callout).opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.spacing).padding(.top, 80).padding(.bottom, 28)
        .background(LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.75)], startPoint: .top, endPoint: .bottom))
    }

    private func planRow(_ offer: ProtoSubscriptionOffer) -> some View {
        let isSelected = offer == c.selected
        return Button { c.select(offer) } label: {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle").font(.title2)
                    .foregroundStyle(isSelected ? Theme.accent : Color(.systemGray3))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(offer.title).font(.body.weight(.semibold))
                        if offer.period == .year, let savings = c.offering.yearlySavingsPercent {
                            Text("−\(savings) %").font(.caption.weight(.bold)).foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Theme.accent))
                        }
                    }
                    Text(offer.period == .year
                         ? "\(offer.formattedPrice) par an, soit \(offer.monthlyPrice) par mois"
                         : "\(offer.formattedPrice) par mois")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? Theme.accent : Color(.systemGray4), lineWidth: isSelected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(ProtoPressStyle())
        .foregroundStyle(.primary)
    }
}

// MARK: - B « Essai expliqué »

struct ProtoPaywallB: View {
    let c: ProtoPaywallContext

    private var trialDays: Int { c.selected.trialDays ?? 0 }

    private var steps: [(when: String, symbol: String, title: String, detail: String)] {
        [
            ("Aujourd'hui", "lock.open.fill", "Tout Premium se débloque",
             "Itinéraires sur mesure, classements complets, analyse de vos progrès, cartes hors ligne et suivi en direct."),
            ("Jour \(trialDays - 5)", "bell.fill", "On vous prévient",
             "Un rappel 5 jours avant la fin de l'essai, pour décider sans surprise."),
            ("Jour \(trialDays)", "star.fill", "Votre abonnement commence",
             "Premier paiement de \(c.selected.formattedPrice). Résiliez avant et vous ne payez rien."),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Passer", action: c.skip).font(.body.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, Theme.spacing).frame(height: 44)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("Comment fonctionne votre essai gratuit")
                        .font(.system(size: 30, weight: .bold)).tracking(-0.4)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(steps.indices, id: \.self) { index in
                            stepRow(steps[index], isLast: index == steps.count - 1)
                        }
                    }

                    VStack(spacing: 14) {
                        Picker("Formule", selection: Binding(get: { c.selected }, set: c.select)) {
                            ForEach(c.offering.offers) { offer in
                                if offer.period == .year, let savings = c.offering.yearlySavingsPercent {
                                    Text("\(offer.title) −\(savings) %").tag(offer)
                                } else {
                                    Text(offer.title).tag(offer)
                                }
                            }
                        }
                        .pickerStyle(.segmented)

                        VStack(spacing: 2) {
                            Text("\(c.selected.trialDays.map { "\($0) jours gratuits, puis " } ?? "")\(c.selected.formattedPrice) / \(c.selected.shortPeriod)")
                                .font(.headline)
                            if c.selected.period == .year {
                                Text("soit \(c.selected.monthlyPrice) par mois").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .contentTransition(.numericText())
                    }

                    ProtoPaywallLegal(c: c)
                }
                .padding(.horizontal, Theme.spacing).padding(.bottom, 24)
            }

            VStack(spacing: 6) {
                ProtoPrimaryButton(title: c.isBusy ? "…" : "Démarrer mes \(trialDays) jours gratuits", isEnabled: !c.isBusy, action: c.startTrial)
                Label("Aucun paiement aujourd'hui", systemImage: "checkmark.shield.fill")
                    .font(.footnote.weight(.medium)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, Theme.spacing).padding(.top, 10).padding(.bottom, 6)
        }
    }

    private func stepRow(_ step: (when: String, symbol: String, title: String, detail: String), isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Image(systemName: step.symbol).font(.subheadline.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.accent))
                if !isLast {
                    Rectangle().fill(Theme.accent.opacity(0.3)).frame(width: 4).frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(step.when.uppercased()).font(.caption.weight(.heavy)).tracking(0.8).foregroundStyle(Theme.accent)
                Text(step.title).font(.body.weight(.semibold))
                Text(step.detail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : 22)
        }
    }
}

// MARK: - C « Gratuit vs Premium »

struct ProtoPaywallC: View {
    let c: ProtoPaywallContext

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(colors: [Theme.accent.opacity(0.45), .clear], center: .top, startRadius: 0, endRadius: 380)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Plus tard", action: c.skip).font(.body.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, Theme.spacing).frame(height: 44)

                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 10) {
                            NervoMark().stroke(Theme.accent, style: NervoMark.strokeStyle(forSide: 44)).frame(width: 44, height: 44)
                            Text(c.firstName.isEmpty ? "Allez plus loin" : "Allez plus loin, \(c.firstName)")
                                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                            Text("Ce que Premium ajoute à Nervo").font(.callout).foregroundStyle(.white.opacity(0.65))
                        }
                        .multilineTextAlignment(.center)

                        table
                        plans
                        ProtoPaywallLegal(c: c)
                    }
                    .padding(.horizontal, Theme.spacing).padding(.bottom, 24)
                }

                ProtoPrimaryButton(title: c.isBusy ? "…" : ctaTitle, isEnabled: !c.isBusy, action: c.startTrial)
                    .padding(.horizontal, Theme.spacing).padding(.top, 10).padding(.bottom, 6)
            }
            .foregroundStyle(.white)
        }
        .environment(\.colorScheme, .dark)
    }

    private var ctaTitle: String {
        c.selected.trialDays.map { "Essayer \($0) jours gratuitement" } ?? "S'abonner"
    }

    private var table: some View {
        VStack(spacing: 0) {
            HStack {
                Text("").frame(maxWidth: .infinity, alignment: .leading)
                Text("Gratuit").frame(width: 64)
                Text("Premium").frame(width: 76).foregroundStyle(Theme.accent)
            }
            .font(.caption.weight(.heavy))
            .padding(.vertical, 10)

            ForEach(ProtoPaywallCopy.comparison, id: \.feature) { row in
                HStack {
                    Text(row.feature).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                    mark(row.free).frame(width: 64)
                    mark(true).frame(width: 76)
                }
                .padding(.vertical, 11)
                Divider().overlay(.white.opacity(0.08))
            }
        }
        .padding(.horizontal, 14)
        .background(alignment: .trailing) {
            // The Premium column, lit up behind the rows.
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accent.opacity(0.14))
                .frame(width: 84).padding(.trailing, 10)
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.06)))
    }

    private func mark(_ included: Bool) -> some View {
        Image(systemName: included ? "checkmark" : "minus")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(included ? Theme.accent : .white.opacity(0.3))
    }

    private var plans: some View {
        HStack(spacing: 10) {
            ForEach(c.offering.offers) { offer in
                let isSelected = offer == c.selected
                Button { c.select(offer) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(offer.title.uppercased()).font(.caption.weight(.heavy)).tracking(0.8)
                            .foregroundStyle(.white.opacity(0.7))
                        Text(offer.monthlyPrice).font(.title2.weight(.bold))
                        Text("par mois").font(.caption).foregroundStyle(.white.opacity(0.6))
                        Text(offer.period == .year ? "facturé \(offer.formattedPrice) par an" : "sans engagement")
                            .font(.caption2).foregroundStyle(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isSelected ? Theme.accent.opacity(0.18) : .white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isSelected ? Theme.accent : .white.opacity(0.12), lineWidth: isSelected ? 2 : 1))
                    .overlay(alignment: .topTrailing) {
                        if offer.period == .year, let savings = c.offering.yearlySavingsPercent {
                            Text("−\(savings) %").font(.caption2.weight(.heavy)).foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Capsule().fill(Theme.accent))
                                .offset(x: -8, y: -9)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(ProtoPressStyle())
                .foregroundStyle(.white)
            }
        }
    }
}
#endif
