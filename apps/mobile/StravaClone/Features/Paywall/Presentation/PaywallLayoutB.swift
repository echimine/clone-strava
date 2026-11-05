import SwiftUI

/// Variant `B`, after AllTrails' paywall (ADR-035 §6): the Annuel / Mensuel cards (the trial's
/// timeline inside the chosen one), "Comparer" down to a Free / Premium table, and a floating
/// black button with "Sans engagement".
struct PaywallLayoutB: View {
    let content: PaywallContent

    private let ink = Color(red: 0.09, green: 0.12, blue: 0.10)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PaywallCloseButton(background: Color(.systemGray6), action: content.skip)

                    Text(content.trialDays == 30 ? "Votre premier mois est offert" : "Passez à Premium")
                        .font(.system(size: 31, weight: .medium))
                        .tracking(-0.6)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 16)
                        .accessibilityAddTraits(.isHeader)

                    HStack {
                        Text("Choisissez votre formule").font(.subheadline.weight(.medium))
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Button("Comparer") { withAnimation { proxy.scrollTo("table", anchor: .top) } }
                            .font(.subheadline.weight(.medium))
                            .underline()
                            .foregroundStyle(.primary)
                            .accessibilityHint("Fait défiler jusqu'au tableau Gratuit et Premium")
                    }
                    .padding(.top, 26)

                    VStack(spacing: 14) {
                        ForEach(content.offering.offers) { planCard($0) }
                    }
                    .padding(.top, 12)

                    table.id("table").padding(.top, 34)

                    PaywallFooter(content: content)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 28)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 160)
            }
        }
        .overlay(alignment: .bottom) { floatingButton }
        // A container, so its buttons keep their own identifiers.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("paywall.layout.B")
    }

    private var floatingButton: some View {
        VStack(spacing: 10) {
            // What is paid after the trial, readable outside the small print (App Store 3.1.2).
            Text(content.selected.priceAfterTrial).font(.subheadline.weight(.semibold))
            Button(action: content.startTrial) {
                Text("Démarrer l'essai gratuit")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 30)
                    .frame(minHeight: 56)
                    .background(Capsule().fill(ink))
                    .contentShape(Capsule())
            }
            .buttonStyle(OnboardingPressStyle())
            .disabled(content.store.isBusy)
            .accessibilityIdentifier("paywall.startTrial")
            Text("Sans engagement").font(.subheadline)
        }
        .padding(.top, 36)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [Color(.systemBackground).opacity(0), Color(.systemBackground)],
                startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.2)
            )
        )
    }

    private func planCard(_ offer: SubscriptionOffer) -> some View {
        let isSelected = offer == content.selected
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return Button { content.select(offer) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: offer.period == .year ? "sparkle" : "circle.hexagongrid.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text(offer.title).font(.system(size: 22, weight: .medium))
                    Spacer()
                    if offer.period == .year, let savings = content.offering.yearlySavingsPercent {
                        Text("−\(savings) % sur l'année")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.accent.opacity(0.12)))
                    }
                }
                Text(offer.period == .year ? "Tout Premium, au meilleur prix" : "Tout Premium, sans engagement")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                Text("\(Text(offer.formattedPrice).fontWeight(.semibold))/\(offer.shortPeriod)\(offer.period == .year ? " (soit \(offer.monthlyPrice)/mois)" : "")")
                    .font(.subheadline)
                if isSelected, let days = offer.trialDays {
                    trialTimeline(offer, days: days)
                        .padding(.top, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(shape.fill(isSelected ? Theme.accent.opacity(0.05) : Color(.systemBackground)))
            .overlay(shape.strokeBorder(isSelected ? ink : Color(.systemGray4), lineWidth: isSelected ? 2.5 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(planLabel(offer))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// "Annuel, 59,99 € par an, soit 5,00 €/mois, moins 50 % sur l'année, 30 jours d'essai gratuit".
    private func planLabel(_ offer: SubscriptionOffer) -> String {
        var parts = ["\(offer.title), \(offer.formattedPrice) \(offer.perPeriod)"]
        if offer.period == .year { parts.append("soit \(offer.monthlyPrice) par mois") }
        if offer.period == .year, let savings = content.offering.yearlySavingsPercent {
            parts.append("moins \(savings) % sur l'année")
        }
        parts.append(offer.period == .year ? "Tout Premium, au meilleur prix" : "Tout Premium, sans engagement")
        if let days = offer.trialDays { parts.append("\(days) jours d'essai gratuit") }
        return parts.joined(separator: ", ")
    }

    private func trialTimeline(_ offer: SubscriptionOffer, days: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            timelineRow("lock.open", Text("\(Text("Aujourd'hui :").fontWeight(.semibold)) début de votre essai gratuit"), isLast: false)
            timelineRow("bell", Text("\(Text("Jour \(days - 2) :").fontWeight(.semibold)) rappel avant la fin de l'essai"), isLast: false)
            timelineRow("star", Text("\(Text("Jour \(days) :").fontWeight(.semibold)) prélèvement de \(offer.formattedPrice)/\(offer.shortPeriod)"), isLast: true)
        }
    }

    private func timelineRow(_ symbol: String, _ text: Text, isLast: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .accessibilityHidden(true)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.accent)
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

    /// Premium-only rows first, the free ones dimmed (as AllTrails does).
    private var table: some View {
        let rows = PaywallCopy.premiumFeatures.map { ($0, false) } + PaywallCopy.freeFeatures.map { ($0, true) }
        return VStack(spacing: 0) {
            HStack {
                Text("Ce que vous obtenez").frame(maxWidth: .infinity, alignment: .leading)
                Text("Gratuit").frame(width: 62)
                Text("Premium").foregroundStyle(.primary).frame(width: 70)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.vertical, 14)
            Divider()
            ForEach(rows, id: \.0) { feature, isFree in
                HStack {
                    Text(feature)
                        .foregroundStyle(isFree ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "checkmark").opacity(isFree ? 1 : 0).frame(width: 62)
                        .accessibilityHidden(true)
                    Image(systemName: "checkmark").frame(width: 70)
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(feature)
                .accessibilityValue(isFree ? "Inclus en Gratuit et en Premium" : "Premium uniquement")
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
