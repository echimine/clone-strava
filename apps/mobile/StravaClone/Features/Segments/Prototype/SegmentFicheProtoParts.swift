#if DEBUG
import MapboxMaps
import SwiftUI

// PROTOTYPE — throwaway (voir SegmentFicheProto.swift). Briques communes aux trois fiches.

// MARK: - Carte du Segment

struct ProtoFicheMap: View {
    let segment: ProtoMapSegment
    var top: Double = 30
    var bottom: Double = 30
    var interactive = false

    var body: some View {
        Map(initialViewport: segment.overview(top: top, bottom: bottom)) {
            PolylineAnnotation(lineCoordinates: segment.line)
                .lineColor(UIColor(Theme.accent)).lineWidth(5).lineJoin(.round)
            RouteEndpointsContent(coordinates: segment.line)
        }
        .mapStyle(.outdoors)
        .allowsHitTesting(interactive)
    }
}

// MARK: - En-tête

struct ProtoSportLine: View {
    let segment: ProtoMapSegment

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: segment.sport.symbol)
            Text(segment.sport.label)
            if segment.isVerified {
                Text("·")
                Label("Segment vérifié", systemImage: "checkmark.seal.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.blue)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
}

/// Distance, D+, pente moyenne, catégorie.
struct ProtoFacts: View {
    let data: ProtoFicheData

    var body: some View {
        HStack(alignment: .top) {
            fact(ProtoMapFormat.distance(data.segment.meters), "Distance")
            fact(ActivityFormatters.elevation(data.gain), "Dénivelé +")
            fact(ProtoMapFormat.grade(data.segment.grade), "Pente moy.")
            fact(data.segment.category ?? "—", "Catégorie")
        }
    }

    private func fact(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Étoile et nombre de favoris, menu ⋯ (Signaler ; Renommer et Supprimer pour le créateur).
struct ProtoFicheToolbar: ViewModifier {
    let store: ProtoMapStore
    let fiche: ProtoFicheState
    let data: ProtoFicheData

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                let starred = store.segment(data.segment.id)?.isStarred ?? false
                Button { store.toggleStar(data.segment.id) } label: {
                    HStack(spacing: 3) {
                        Image(systemName: starred ? "star.fill" : "star").foregroundStyle(starred ? .yellow : .primary)
                        Text((data.starCount + (starred ? 1 : 0)).formatted(.number.locale(ActivityFormatters.locale)))
                            .font(.footnote).monospacedDigit()
                    }
                }
                .accessibilityLabel(starred ? "Retirer des favoris" : "Ajouter aux favoris")
                Menu {
                    if fiche.isMine {
                        Button("Renommer", systemImage: "pencil") { fiche.message = "Renommer (feuille de « Mes Segments »)" }
                        Button("Supprimer", systemImage: "trash", role: .destructive) {
                            fiche.message = data.segment.athletes > 1 ? "Impossible : d'autres athlètes y ont un Effort" : "Supprimé"
                        }
                    }
                    Button("Signaler ce Segment", systemImage: "flag") { fiche.message = "Signalement envoyé (motif à choisir)" }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
    }
}

/// Rétro-appariement en cours, juste après la création (#232).
struct ProtoFreshBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Recherche des Efforts passés sur ce Segment… Le Classement se remplit au fur et à mesure.")
                .font(.footnote)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.1), in: .rect(cornerRadius: 12))
    }
}

// MARK: - Médailles, Légende locale

struct ProtoMedal: View {
    let place: Int
    var size: CGFloat = 22

    private static let colors = [Color(red: 0.93, green: 0.73, blue: 0.13), Color(white: 0.66), Color(red: 0.78, green: 0.5, blue: 0.26)]

    var body: some View {
        ZStack {
            Circle().fill(Self.colors[place - 1])
            Text("\(place)").font(.system(size: size * 0.55, weight: .bold)).foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(["Médaille d'or", "Médaille d'argent", "Médaille de bronze"][place - 1])
    }
}

struct ProtoLaurel: View {
    let name: String
    var size: CGFloat = 44

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "laurel.leading").font(.system(size: size * 0.7)).foregroundStyle(.orange)
            AvatarView(name: name, url: nil, size: size)
            Image(systemName: "laurel.trailing").font(.system(size: size * 0.7)).foregroundStyle(.orange)
        }
    }
}

struct ProtoLegendCard: View {
    let data: ProtoFicheData
    let sex: ProtoSexFilter

    var body: some View {
        if let legend = data.legend(sex: sex) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ProtoLaurel(name: legend.rider.name)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sex == .all ? "Légende locale" : "Légende locale · \(sex.rawValue)")
                            .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                        Text(legend.rider.isMe ? "Toi" : legend.rider.name).font(.headline)
                        Text("\(legend.count) Efforts ces 90 derniers jours").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if !legend.rider.isMe {
                    let missing = legend.count - data.myRecentCount + 1
                    Text(data.myRecentCount == 0
                         ? "Fais \(missing) Efforts en 90 jours pour devenir Légende locale."
                         : "Toi : \(data.myRecentCount) Efforts. Encore \(missing) pour devenir Légende locale.")
                        .font(.footnote)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("Personne n'est passé ici ces 90 derniers jours : le premier devient Légende locale.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Mes efforts

struct ProtoMyRecordRow: View {
    let data: ProtoFicheData
    let rankInAll: Int?

    var body: some View {
        if let best = data.myBest {
            HStack(spacing: 12) {
                Image(systemName: "trophy.fill").font(.title2).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mon record").font(.caption).foregroundStyle(.secondary)
                    Text(ProtoFicheData.time(best.seconds)).font(.title2.bold()).monospacedDigit()
                    Text(ProtoFicheData.date(best.date) + (best.isPublic ? "" : " · Activité privée"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let rankInAll {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Mon rang").font(.caption).foregroundStyle(.secondary)
                        Text("\(rankInAll)e").font(.title3.bold()).monospacedDigit()
                    }
                }
            }
        }
    }
}

struct ProtoMyEffortRow: View {
    let effort: ProtoMyEffort
    let rank: Int?

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let medal = effort.medal { ProtoMedal(place: medal) } else { Color.clear }
            }
            .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(ProtoFicheData.date(effort.date)).font(.subheadline)
                if !effort.isPublic {
                    Label("Privée · hors Classement", systemImage: "lock.fill").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if effort.isBoardLine, let rank {
                Text("\(rank)e").font(.caption.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color(.secondarySystemFill), in: Capsule())
            }
            Text(ProtoFicheData.time(effort.seconds)).font(.body.weight(.semibold)).monospacedDigit()
        }
    }
}

struct ProtoNoEffort: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pas encore d'Effort ici").font(.headline)
            Text("Passe sur ce Segment pendant une Activité : ton temps, ta Médaille et ton rang s'afficheront ici.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Filtres du Classement

/// Tous / Hommes / Femmes ; sans Premium, Hommes et Femmes portent un cadenas.
struct ProtoSexPicker: View {
    let fiche: ProtoFicheState
    @Binding var sex: ProtoSexFilter

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ProtoSexFilter.allCases) { option in
                let locked = !fiche.isPremium && option != .all
                Button {
                    if locked { fiche.locked("leaderboard_filter") } else { sex = option }
                } label: {
                    HStack(spacing: 3) {
                        if locked { Image(systemName: "lock.fill").font(.caption2) }
                        Text(option.rawValue)
                    }
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .foregroundStyle(locked ? .secondary : .primary)
                    .background(sex == option ? Color(.systemBackground) : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color(.tertiarySystemFill), in: Capsule())
    }
}

/// Un seul autre filtre, dans un menu ; sans Premium, le bouton ouvre le Paywall.
struct ProtoOtherFilterMenu: View {
    let fiche: ProtoFicheState
    @Binding var other: ProtoOtherFilter

    var body: some View {
        if fiche.isPremium {
            Menu {
                Picker("Filtre", selection: $other) {
                    Text("Aucun filtre").tag(ProtoOtherFilter.none)
                    Section("Période") { ForEach(ProtoOtherFilter.periods, id: \.self) { Text($0.label).tag($0) } }
                    Text("Abonnements").tag(ProtoOtherFilter.following)
                }
                Menu("Tranche d'âge") {
                    Picker("Âge", selection: $other) {
                        ForEach(ProtoOtherFilter.ageBands.indices, id: \.self) { Text(ProtoOtherFilter.ageBands[$0].0).tag(ProtoOtherFilter.age($0)) }
                    }
                }
                Menu("Tranche de poids") {
                    Picker("Poids", selection: $other) {
                        ForEach(ProtoOtherFilter.weightBands.indices, id: \.self) { Text(ProtoOtherFilter.weightBands[$0].0).tag(ProtoOtherFilter.weight($0)) }
                    }
                }
            } label: { label(other.label, locked: false) }
        } else {
            Button { fiche.locked("leaderboard_filter") } label: { label("Filtres", locked: true) }
                .buttonStyle(.plain)
        }
    }

    private func label(_ title: String, locked: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: locked ? "lock.fill" : "line.3.horizontal.decrease")
            Text(title)
            if !locked { Image(systemName: "chevron.down").font(.caption2) }
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(other == .none ? Color(.tertiarySystemFill) : Theme.accent.opacity(0.18), in: Capsule())
    }
}

// MARK: - Lignes du Classement

struct ProtoBoardRowView: View {
    let row: ProtoBoardRow

    var body: some View {
        HStack(spacing: 10) {
            Text("\(row.rank)").font(.subheadline.weight(.semibold)).monospacedDigit().frame(width: 30, alignment: .leading)
            AvatarView(name: row.rider.name, url: nil, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.rider.isMe ? "\(row.rider.name) (toi)" : row.rider.name).font(.subheadline.weight(row.rider.isMe ? .bold : .regular))
                Text(ProtoFicheData.date(row.date)).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(ProtoFicheData.time(row.seconds)).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, row.rider.isMe ? 8 : 0)
        .background(row.rider.isMe ? Theme.accent.opacity(0.12) : .clear, in: .rect(cornerRadius: 8))
    }
}

/// Encart à la place de la suite du Classement, sans Premium.
struct ProtoPremiumInset: View {
    let fiche: ProtoFicheState
    let total: Int

    var body: some View {
        Button { fiche.locked("segment_leaderboard") } label: {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill").foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Voir le classement complet avec Premium").font(.subheadline.weight(.semibold))
                    Text("\(total) athlètes, filtres par sexe, période, âge, poids et Abonnements").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Theme.accent.opacity(0.08), in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

/// Premium : toutes les lignes. Sans Premium : top 10, ma ligne épinglée si je suis plus loin, l'encart.
/// `pinsMe` : faux quand la variante colle ma ligne ailleurs.
struct ProtoBoardList: View {
    let fiche: ProtoFicheState
    let board: ProtoBoard
    var pinsMe = true

    var body: some View {
        let shown = fiche.isPremium ? board.rows : Array(board.rows.prefix(10))
        LazyVStack(spacing: 0) {
            if board.rows.isEmpty {
                Text("Personne dans ce filtre.").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 12)
            }
            ForEach(shown) { row in
                ProtoBoardRowView(row: row)
                Divider()
            }
            if !fiche.isPremium, pinsMe, let me = board.me, me.rank > 10 {
                Image(systemName: "ellipsis").foregroundStyle(.tertiary).padding(.vertical, 4)
                ProtoBoardRowView(row: me)
            }
            if !fiche.isPremium, board.rows.count > 10 {
                ProtoPremiumInset(fiche: fiche, total: board.rows.count).padding(.top, 12)
            }
        }
    }
}
#endif
