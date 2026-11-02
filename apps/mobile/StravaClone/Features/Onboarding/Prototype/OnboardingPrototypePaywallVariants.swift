#if DEBUG
import SwiftUI

// PROTOTYPE — throwaway (see OnboardingPrototypePaywall.swift). Three proven paywall patterns,
// fed by the same `ProtoPaywallContext`, to A/B test with RevenueCat Experiments:
// A « Frise de l'essai »: trial timeline (Blinkist, +23 % trials; also Strava + Runna, Fitbit),
//   yearly offer only, monthly behind « Voir toutes les offres » (Mojo, +15-20 % yearly).
// B « Personnalisé »: title and perks from the Onboarding answers, plans side by side (Bevel).
// C « Gratuit vs Premium »: Free / Premium comparison table (Any Distance, AllTrails).

// MARK: - A « Frise de l'essai »

struct ProtoPaywallA: View {
    let c: ProtoPaywallContext

    @State private var showsAllOffers = false

    private var trialDays: Int { c.selected.trialDays ?? 0 }

    private struct Step: Identifiable {
        let when: String, symbol: String, title: String, detail: String
        var isDone = false
        var id: String { when }
    }

    private var steps: [Step] {
        [
            Step(when: "C'est fait", symbol: "checkmark", title: "Votre compte est créé",
                 detail: "Votre profil est prêt avec vos sports et vos objectifs.", isDone: true),
            Step(when: "Aujourd'hui", symbol: "lock.open.fill", title: "Tout Premium se débloque",
                 detail: ProtoPaywallCopy.perks.map(\.title).joined(separator: ", ") + "."),
            Step(when: "Jour \(trialDays - 5)", symbol: "bell.fill", title: "On vous prévient",
                 detail: "Une notification 5 jours avant la fin de l'essai, pour décider sans surprise."),
            Step(when: "Jour \(trialDays)", symbol: "star.fill", title: "Votre abonnement commence",
                 detail: "Premier paiement de \(c.selected.formattedPrice). Résiliez avant et vous ne payez rien."),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Passer", action: c.skip).font(.body.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, Theme.spacing).frame(height: 44)

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("NERVO PREMIUM").font(.caption.weight(.heavy)).tracking(1.2).foregroundStyle(Theme.accent)
                        Text(trialDays > 0 ? "Essayez Premium gratuitement pendant \(trialDays) jours" : "Passez à Premium")
                            .font(.system(size: 30, weight: .bold)).tracking(-0.4)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(steps) { step in stepRow(step, isLast: step.id == steps.last?.id) }
                    }

                    offers
                    ProtoPaywallLegal(c: c)
                }
                .padding(.horizontal, Theme.spacing).padding(.bottom, 24)
            }

            VStack(spacing: 6) {
                ProtoPrimaryButton(title: c.isBusy ? "…" : "Commencer mon essai gratuit", isEnabled: !c.isBusy, action: c.startTrial)
                Label("Aucun paiement aujourd'hui", systemImage: "checkmark.shield.fill")
                    .font(.footnote.weight(.medium)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, Theme.spacing).padding(.top, 10).padding(.bottom, 6)
        }
    }

    /// The yearly offer alone, anchored to its monthly price; the others one tap away.
    @ViewBuilder
    private var offers: some View {
        if showsAllOffers {
            VStack(spacing: 10) {
                ForEach(c.offering.offers) { offer in ProtoPlanRow(c: c, offer: offer) }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        } else {
            VStack(spacing: 8) {
                VStack(spacing: 2) {
                    Text("\(c.selected.trialDays.map { "\($0) jours gratuits, puis " } ?? "")\(c.selected.formattedPrice) / \(c.selected.shortPeriod)")
                        .font(.headline)
                    if c.selected.period == .year {
                        Text("soit \(c.selected.monthlyPrice) par mois").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Button("Voir toutes les offres") { withAnimation(.snappy) { showsAllOffers = true } }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func stepRow(_ step: Step, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Image(systemName: step.symbol).font(.subheadline.weight(.bold))
                    .foregroundStyle(step.isDone ? Theme.accent : .white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(step.isDone ? Theme.accent.opacity(0.15) : Theme.accent))
                if !isLast {
                    Rectangle().fill(Theme.accent.opacity(0.3)).frame(width: 4).frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(step.when.uppercased()).font(.caption.weight(.heavy)).tracking(0.8)
                    .foregroundStyle(step.isDone ? .secondary : Theme.accent)
                Text(step.title).font(.body.weight(.semibold))
                Text(step.detail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : 20)
        }
    }
}

/// A selectable plan row with its radio, price and yearly saving.
struct ProtoPlanRow: View {
    let c: ProtoPaywallContext
    let offer: ProtoSubscriptionOffer

    var body: some View {
        let isSelected = offer == c.selected
        Button { c.select(offer) } label: {
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

// MARK: - B « Personnalisé »

struct ProtoPaywallB: View {
    let c: ProtoPaywallContext

    /// Spoken to the first goal picked in the Onboarding.
    private var title: String {
        switch c.goals.first {
        case .compete: "Visez le haut des classements"
        case .explore: "Partez à la découverte"
        case .health: "Suivez vos progrès de près"
        case .people: "Partagez chaque sortie, en toute sérénité"
        case .event: "Préparez votre objectif"
        case .habit: "Gardez le rythme"
        case nil: "Allez plus loin avec Premium"
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if !c.sports.isEmpty { parts.append(c.sports.map { ActivityFormatters.sportLabel($0).lowercased() }.joined(separator: ", ")) }
        if let level = c.level { parts.append("niveau \(level.rawValue.lowercased())") }
        return parts.isEmpty ? "Nervo Premium, pensé pour votre pratique." : "Nervo Premium, pensé pour vous : \(parts.joined(separator: " · "))."
    }

    /// At most two, the ones matching the most goals: tag more and « Pour vous » means nothing.
    private var forYou: [ProtoPerk] {
        let goals = Set(c.goals)
        let matching = ProtoPaywallCopy.perks
            .map { (perk: $0, score: $0.goals.intersection(goals).count) }
            .filter { $0.score > 0 }
        return Array(matching.sorted { $0.score > $1.score }.prefix(2).map(\.perk))
    }
    private var others: [ProtoPerk] { ProtoPaywallCopy.perks.filter { perk in !forYou.contains { $0.id == perk.id } } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.system(size: 30, weight: .bold)).tracking(-0.4)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.trailing, 36)

                VStack(alignment: .leading, spacing: 16) {
                    ForEach(forYou) { perk in perkRow(perk, isForYou: true) }
                    if !forYou.isEmpty, !others.isEmpty {
                        Text("ET AUSSI").font(.caption.weight(.heavy)).tracking(1).foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                    ForEach(others) { perk in perkRow(perk, isForYou: false) }
                }

                ProtoPaywallLegal(c: c)
            }
            .padding(.horizontal, Theme.spacing).padding(.top, 16).padding(.bottom, 24)
        }
        .overlay(alignment: .topTrailing) {
            Button(action: c.skip) {
                Image(systemName: "xmark").font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
                    .frame(width: 32, height: 32).background(Circle().fill(Color(.secondarySystemBackground)))
            }
            .accessibilityLabel("Passer")
            .padding(.trailing, Theme.spacing).padding(.top, 12)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    ForEach(c.offering.offers) { offer in planCard(offer) }
                }
                ProtoPrimaryButton(title: c.isBusy ? "…" : (c.selected.trialDays.map { "Essayer gratuitement \($0) jours" } ?? "S'abonner"),
                                   isEnabled: !c.isBusy, action: c.startTrial)
            }
            .padding(.horizontal, Theme.spacing).padding(.top, 12).padding(.bottom, 6)
            .background(.bar)
        }
    }

    private func perkRow(_ perk: ProtoPerk, isForYou: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: perk.symbol).font(.body.weight(.semibold))
                .foregroundStyle(isForYou ? .white : Theme.accent)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isForYou ? Theme.accent : Theme.accent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(perk.title).font(.body.weight(.semibold))
                    if isForYou {
                        Text("Pour vous").font(.caption2.weight(.bold)).foregroundStyle(Theme.accent)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Theme.accent.opacity(0.12)))
                    }
                }
                Text(perk.detail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func planCard(_ offer: ProtoSubscriptionOffer) -> some View {
        let isSelected = offer == c.selected
        return Button { c.select(offer) } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(offer.title).font(.subheadline.weight(.bold))
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Theme.accent : Color(.systemGray3))
                }
                Text("\(offer.formattedPrice) / \(offer.shortPeriod)").font(.subheadline.weight(.semibold))
                Text(offer.period == .year ? "soit \(offer.monthlyPrice) / mois" : "sans engagement")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.systemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? Theme.accent : Color(.systemGray4), lineWidth: isSelected ? 2 : 1))
            .overlay(alignment: .topLeading) {
                if offer.period == .year, let savings = c.offering.yearlySavingsPercent {
                    Text("−\(savings) %").font(.caption2.weight(.heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.accent))
                        .offset(x: 10, y: -9)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(ProtoPressStyle())
        .foregroundStyle(.primary)
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
