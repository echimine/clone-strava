#if DEBUG
import SwiftUI

// PROTOTYPE — throwaway. Ticket « Prototype : fiche d'un Segment » (#238), carte « Segments et
// Records dans l'app » (#223). Branche prototype/segment-detail (partie de prototype/segment-map),
// jamais fusionnée.
//
// Lancement : argument `-SegmentDetailPrototype` à la place de l'app : l'onglet Carte (variante A du
// prototype de carte) avec la fiche du « Col de la Forclaz depuis Talloires » déjà ouverte.
// Options : `-protoFiche A|B|C`, `-protoPremium YES`, `-protoSegment <id>` (1 à 13).
// La pastille violette en bas cycle les variantes ; son menu « États » bascule Premium, avec ou
// sans Effort, « c'est mon Segment » et « tout juste créé » (rétro-appariement en cours).
//   A — Tout sur une page : carte, chiffres, profil, Mes efforts, Légende locale, Classement (Strava).
//   B — Carte plein écran et panneau à onglets Aperçu | Mes efforts | Classement.
//   C — Résumé en tuiles, Classement et Mes efforts sur des écrans poussés, ma ligne collée en bas.
// Les athlètes, temps et dates sont inventés (graine par Segment). Rien n'est envoyé.

enum SegmentFicheProto {
    static let launchArgument = "-SegmentDetailPrototype"

    static var isActive: Bool { ProcessInfo.processInfo.arguments.contains(launchArgument) }

    static var startSegmentID: Int {
        let id = UserDefaults.standard.integer(forKey: "protoSegment")
        return id == 0 ? 1 : id
    }
}

// MARK: - États basculés par la pastille

@MainActor @Observable
final class ProtoFicheState {
    var variant = UserDefaults.standard.string(forKey: "protoFiche") ?? "A"
    var isPremium = UserDefaults.standard.bool(forKey: "protoPremium")
    var hasEfforts = true
    var isMine = false
    var isFresh = false
    /// Non nil : le Paywall est ouvert en feuille, depuis ce cadenas (`paywall_viewed {entry}`).
    var paywallEntry: String?
    var message: String?

    func locked(_ entry: String) { paywallEntry = entry }
}

// MARK: - Racine de la fiche : aiguille vers la variante

struct ProtoSegmentFiche: View {
    let store: ProtoMapStore
    let fiche: ProtoFicheState
    let id: Int

    var body: some View {
        if let segment = store.segment(id) {
            let data = ProtoFicheData(segment: segment, hasEfforts: fiche.hasEfforts)
            Group {
                switch fiche.variant {
                case "B": ProtoFicheVariantB(store: store, fiche: fiche, data: data)
                case "C": ProtoFicheVariantC(store: store, fiche: fiche, data: data)
                default: ProtoFicheVariantA(store: store, fiche: fiche, data: data)
                }
            }
            .id(fiche.variant)
        }
    }
}

// MARK: - Pastille violette : pas une partie du design évalué

struct ProtoFicheBar: View {
    @Bindable var fiche: ProtoFicheState
    static let variants = [("A", "Tout sur une page"), ("B", "Carte + panneau à onglets"), ("C", "Tuiles + écrans poussés")]

    var body: some View {
        HStack(spacing: 4) {
            Button { cycle(-1) } label: { Image(systemName: "chevron.left").frame(width: 30, height: 30) }
            VStack(spacing: 0) {
                Text("Fiche \(fiche.variant)").font(.caption.weight(.bold))
                Text(Self.variants.first { $0.0 == fiche.variant }?.1 ?? "").font(.caption2)
            }
            .frame(minWidth: 150)
            Button { cycle(1) } label: { Image(systemName: "chevron.right").frame(width: 30, height: 30) }
            Menu {
                Toggle("Premium", isOn: $fiche.isPremium)
                Toggle("Avec mes Efforts", isOn: $fiche.hasEfforts)
                Toggle("C'est mon Segment", isOn: $fiche.isMine)
                Toggle("Tout juste créé", isOn: $fiche.isFresh)
            } label: {
                Image(systemName: "slider.horizontal.3").frame(width: 30, height: 30)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.purple.opacity(0.92), in: Capsule())
        .shadow(radius: 6)
        .buttonStyle(.plain)
    }

    private func cycle(_ step: Int) {
        let keys = Self.variants.map(\.0)
        let index = keys.firstIndex(of: fiche.variant) ?? 0
        fiche.variant = keys[(index + step + keys.count) % keys.count]
    }
}

/// Le vrai Paywall, en feuille, depuis un cadenas ; « Passer » ou « Démarrer l'essai » ferment.
struct ProtoPaywallSheet: View {
    let fiche: ProtoFicheState

    var body: some View {
        PaywallView(
            store: PaywallStore(service: UnwiredSubscriptionService()) { fiche.paywallEntry = nil },
            firstName: "Eliott"
        )
        .overlay(alignment: .bottom) {
            Text("paywall_viewed { entry: \(fiche.paywallEntry ?? "") }")
                .font(.caption2.monospaced())
                .padding(6)
                .background(Color.purple.opacity(0.9), in: Capsule())
                .foregroundStyle(.white)
                .padding(.bottom, 4)
        }
    }
}
#endif
