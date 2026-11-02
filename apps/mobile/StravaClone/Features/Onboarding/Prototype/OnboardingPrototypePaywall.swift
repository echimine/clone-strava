#if DEBUG
import SwiftUI

// PROTOTYPE — throwaway, never merged to main (wayfinder ticket « Design du Paywall non branché »,
// #110). Question: what does the unwired Paywall look like, and where does the
// `SubscriptionService` port sit so that plugging RevenueCat in later does not change the screen?
// Three structurally different variants (OnboardingPrototypePaywallVariants.swift), switchable
// from the floating pill once on the Paywall stage. Launch straight on it:
// `xcrun simctl launch booted fr.echimine.stravaclone -prototypeOnboarding -protoStage paywall`.

// MARK: - Port (ADR-014: `Features/Paywall/Domain` in the real code)

/// What the Paywall knows about subscriptions. The screen only talks to this protocol: today the
/// unwired adapter below answers with hard-coded offers; later a RevenueCat adapter in
/// `Infrastructure/` maps the current offering (localised prices, trial, metadata) onto the same
/// types, and the screen does not change. Built in `Di.swift`, where the ADR-014 TODO sits.
protocol ProtoSubscriptionService: Sendable {
    /// RevenueCat's current offering. Throws when it cannot be loaded (offline, outage).
    func paywallOffering() async throws -> ProtoPaywallOffering
    /// « Démarrer l'essai ». The unwired adapter never grants Premium.
    func startTrial(_ offer: ProtoSubscriptionOffer) async -> ProtoPurchaseOutcome
    /// « Restaurer les achats », required by the App Store.
    func restorePurchases() async -> ProtoRestoreOutcome
}

struct ProtoSubscriptionOffer: Identifiable, Hashable, Sendable {
    enum Period: Sendable { case month, year }

    /// The App Store product id (RevenueCat package).
    let id: String
    let period: Period
    let price: Decimal
    let currencyCode: String
    /// `nil`: no free trial on this offer.
    let trialDays: Int?

    private var style: Decimal.FormatStyle.Currency {
        .currency(code: currencyCode).locale(Locale(identifier: "fr_FR"))
    }
    /// « 59,99 € » (RevenueCat gives it already localised by StoreKit).
    var formattedPrice: String { price.formatted(style) }
    /// « 5,00 € », the price brought back to one month.
    var monthlyPrice: String { (period == .year ? price / 12 : price).formatted(style.precision(.fractionLength(2))) }
    var title: String { period == .year ? "Annuel" : "Mensuel" }
    var perPeriod: String { period == .year ? "par an" : "par mois" }
    var shortPeriod: String { period == .year ? "an" : "mois" }
}

struct ProtoPaywallOffering: Sendable {
    let offers: [ProtoSubscriptionOffer]
    /// Pre-selected and badged; RevenueCat offering metadata in the real code (ADR-014).
    let recommendedID: String

    var recommended: ProtoSubscriptionOffer { offers.first { $0.id == recommendedID } ?? offers[0] }

    /// « −50 % »: the yearly offer against twelve monthly ones.
    var yearlySavingsPercent: Int? {
        guard let year = offers.first(where: { $0.period == .year }),
              let month = offers.first(where: { $0.period == .month }) else { return nil }
        let ratio = NSDecimalNumber(decimal: year.price / (month.price * 12)).doubleValue
        return Int(((1 - ratio) * 100).rounded())
    }
}

enum ProtoPurchaseOutcome: Sendable { case subscribed, cancelled, unavailable }
enum ProtoRestoreOutcome: Sendable { case restored, nothingToRestore, unavailable }

/// How the stub answers, switched from the pill: shows what the Paywall does while RevenueCat is
/// slow or down (only possible once wired; the unwired adapter itself never fails).
enum ProtoOfferingMode: String, CaseIterable {
    case ok = "offres OK", slow = "offres lentes", unavailable = "offres KO"
}

/// The adapter of the « Paywall non branché » spec: hard-coded offers, no purchase.
struct ProtoUnwiredSubscriptionService: ProtoSubscriptionService {
    var mode: ProtoOfferingMode = .ok

    static let offering = ProtoPaywallOffering(
        offers: [
            ProtoSubscriptionOffer(id: "nervo_premium_yearly", period: .year, price: Decimal(string: "59.99")!, currencyCode: "EUR", trialDays: 30),
            ProtoSubscriptionOffer(id: "nervo_premium_monthly", period: .month, price: Decimal(string: "9.99")!, currencyCode: "EUR", trialDays: 30),
        ],
        recommendedID: "nervo_premium_yearly"
    )

    struct Unavailable: Error {}

    func paywallOffering() async throws -> ProtoPaywallOffering {
        switch mode {
        case .ok: return Self.offering
        case .slow:
            try await Task.sleep(for: .seconds(2.5))
            return Self.offering
        case .unavailable:
            try await Task.sleep(for: .seconds(1))
            throw Unavailable()
        }
    }

    func startTrial(_ offer: ProtoSubscriptionOffer) async -> ProtoPurchaseOutcome {
        try? await Task.sleep(for: .milliseconds(600))
        return .unavailable
    }

    func restorePurchases() async -> ProtoRestoreOutcome {
        try? await Task.sleep(for: .milliseconds(600))
        return .unavailable
    }
}

// MARK: - Content under review (shared by the three variants)

struct ProtoPerk: Identifiable {
    let symbol: String
    let title: String
    let detail: String
    var id: String { title }
}

enum ProtoPaywallCopy {
    static let perks: [ProtoPerk] = [
        ProtoPerk(symbol: "map.fill", title: "Itinéraires sur mesure",
                  detail: "Un parcours tracé depuis chez vous, selon la distance et le dénivelé voulus."),
        ProtoPerk(symbol: "trophy.fill", title: "Classements complets",
                  detail: "Tous les classements de segments, filtrés par âge et par genre."),
        ProtoPerk(symbol: "chart.line.uptrend.xyaxis", title: "Analyse de vos progrès",
                  detail: "Tendances, records personnels et comparaison semaine après semaine."),
        ProtoPerk(symbol: "arrow.down.circle.fill", title: "Cartes hors ligne",
                  detail: "Téléchargez vos itinéraires et partez sans réseau."),
        ProtoPerk(symbol: "dot.radiowaves.left.and.right", title: "Suivi en direct",
                  detail: "Vos proches suivent votre position pendant l'effort."),
    ]

    /// Free vs Premium (variant C). `true`: also in the free app.
    static let comparison: [(feature: String, free: Bool)] = [
        ("Enregistrer vos activités", true),
        ("Fil d'actualité, kudos et commentaires", true),
        ("Segments et Records perso", true),
        ("Classements complets", false),
        ("Itinéraires sur mesure", false),
        ("Analyse de vos progrès", false),
        ("Cartes hors ligne", false),
        ("Suivi en direct", false),
    ]

    /// Auto-renewal terms the App Store asks for next to the purchase button (guideline 3.1.2).
    static func legal(_ offer: ProtoSubscriptionOffer) -> String {
        let start = offer.trialDays.map { "Essai gratuit de \($0) jours, puis \(offer.formattedPrice) \(offer.perPeriod)." }
            ?? "\(offer.formattedPrice) \(offer.perPeriod)."
        return start + " Le paiement est débité sur votre compte Apple à la fin de l'essai. L'abonnement se renouvelle automatiquement, sauf résiliation au moins 24 heures avant la fin de la période en cours, dans les Réglages de votre compte Apple."
    }
}

// MARK: - Screen: loads the offering through the port, then hands it to a variant

enum ProtoPaywallVariant: String, CaseIterable {
    case a = "A", b = "B", c = "C"
    var name: String {
        switch self {
        case .a: "Avantages"
        case .b: "Essai expliqué"
        case .c: "Gratuit vs Premium"
        }
    }
}

/// Everything a variant needs: the variants only lay it out.
struct ProtoPaywallContext {
    let firstName: String
    let offering: ProtoPaywallOffering
    let selected: ProtoSubscriptionOffer
    let isBusy: Bool
    let select: (ProtoSubscriptionOffer) -> Void
    let startTrial: () -> Void
    let skip: () -> Void
    let restore: () -> Void
    let openLegal: (String) -> Void
}

struct ProtoPaywall: View {
    let answers: ProtoAnswers
    let variant: ProtoPaywallVariant
    let service: any ProtoSubscriptionService
    /// Continues the journey (notifications permission) with what happened, for the state sheet.
    let finish: (String) -> Void

    private enum Phase { case loading, loaded(ProtoPaywallOffering) }
    @State private var phase = Phase.loading
    @State private var selectedID: String?
    @State private var isBusy = false
    @State private var toast: String?
    @State private var legalPage: ProtoLegalPage?

    var body: some View {
        ZStack {
            switch phase {
            case .loading:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Chargement des offres…").font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .loaded(offering):
                variantView(context(offering))
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast).font(.footnote.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(.black.opacity(0.85)))
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(item: $legalPage) { page in
            NavigationStack {
                ContentUnavailableView(page.title, systemImage: "doc.text",
                                       description: Text("Page à rédiger et à héberger (hors prototype)."))
                    .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium])
        }
        .sensoryFeedback(.selection, trigger: selectedID)
        .task { await load() }
    }

    @ViewBuilder
    private func variantView(_ context: ProtoPaywallContext) -> some View {
        switch variant {
        case .a: ProtoPaywallA(c: context)
        case .b: ProtoPaywallB(c: context)
        case .c: ProtoPaywallC(c: context)
        }
    }

    private func context(_ offering: ProtoPaywallOffering) -> ProtoPaywallContext {
        let selected = offering.offers.first { $0.id == selectedID } ?? offering.recommended
        return ProtoPaywallContext(
            firstName: answers.firstName.trimmingCharacters(in: .whitespaces),
            offering: offering,
            selected: selected,
            isBusy: isBusy,
            select: { offer in withAnimation(.snappy(duration: 0.25)) { selectedID = offer.id } },
            startTrial: { Task { await startTrial(selected) } },
            skip: { finish("Passé (offre affichée : \(selected.title.lowercased()))") },
            restore: { Task { await restore() } },
            openLegal: { legalPage = ProtoLegalPage(title: $0) }
        )
    }

    private func load() async {
        do {
            let offering = try await service.paywallOffering()
            withAnimation(.easeOut(duration: 0.3)) { phase = .loaded(offering) }
        } catch {
            // Proposed rule: without offers there is nothing to show, so the Paywall is skipped
            // rather than blocking the end of the Onboarding.
            finish("Sauté : offres indisponibles")
        }
    }

    private func startTrial(_ offer: ProtoSubscriptionOffer) async {
        isBusy = true
        let outcome = await service.startTrial(offer)
        isBusy = false
        switch outcome {
        case .subscribed: finish("Essai démarré (\(offer.id))")
        case .cancelled: show("Achat annulé")
        // Unwired: the button continues the journey without granting Premium.
        case .unavailable: finish("« Démarrer l'essai » (\(offer.id)), non branché : aucun Premium")
        }
    }

    private func restore() async {
        isBusy = true
        let outcome = await service.restorePurchases()
        isBusy = false
        switch outcome {
        case .restored: finish("Achats restaurés")
        case .nothingToRestore: show("Aucun achat à restaurer")
        case .unavailable: show("Restauration non branchée")
        }
    }

    private func show(_ message: String) {
        withAnimation(.snappy) { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.snappy) { toast = nil }
        }
    }
}

private struct ProtoLegalPage: Identifiable {
    let title: String
    var id: String { title }
}

// MARK: - Shared pieces

/// Renewal terms and the three links the App Store requires.
struct ProtoPaywallLegal: View {
    let c: ProtoPaywallContext
    var alignment: TextAlignment = .center

    var body: some View {
        VStack(spacing: 12) {
            Text(ProtoPaywallCopy.legal(c.selected))
                .font(.caption2).foregroundStyle(.secondary)
                .multilineTextAlignment(alignment)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Button("Conditions d'utilisation") { c.openLegal("Conditions d'utilisation") }
                Text("·")
                Button("Confidentialité") { c.openLegal("Politique de confidentialité") }
                Text("·")
                Button("Restaurer les achats", action: c.restore)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
        }
    }
}

/// Stand-in for the step after the Paywall (not part of this ticket).
struct ProtoNotificationsStub: View {
    let answers: ProtoAnswers
    let restart: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bell.badge").font(.system(size: 56)).foregroundStyle(Theme.accent)
            Text("Permission notifications").font(.title.bold())
            Text("Hors prototype. Sortie du Paywall :").font(.callout).foregroundStyle(.secondary)
            Text(answers.paywallEvents.last ?? "—").font(.callout.monospaced()).multilineTextAlignment(.center)
            Spacer()
            ProtoPrimaryButton(title: "Recommencer l'Onboarding", isEnabled: true, action: restart)
        }
        .padding(Theme.spacing)
    }
}
#endif
