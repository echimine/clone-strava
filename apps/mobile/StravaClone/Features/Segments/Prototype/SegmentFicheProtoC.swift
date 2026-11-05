#if DEBUG
import SwiftUI

// PROTOTYPE — throwaway (voir SegmentFicheProto.swift).
// Variante C — « Tuiles + écrans poussés » : une fiche courte (vignette de carte et chiffres, profil,
// quatre tuiles Mon record / Mon rang / Légende locale / Mes efforts, podium du Classement). Le
// Classement complet et Mes efforts s'ouvrent sur leur propre écran. Le Classement y a ses filtres
// en puces (sexe + un autre) et ma ligne collée en bas de l'écran.

struct ProtoFicheVariantC: View {
    let store: ProtoMapStore
    let fiche: ProtoFicheState
    let data: ProtoFicheData

    var body: some View {
        let all = data.board(sex: .all, other: .none)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    ProtoFicheMap(segment: data.segment, top: 12, bottom: 12)
                        .frame(width: 120, height: 120)
                        .clipShape(.rect(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(data.segment.name).font(.title3.bold())
                        ProtoSportLine(segment: data.segment)
                        Text([ProtoMapFormat.distance(data.segment.meters), ActivityFormatters.elevation(data.gain) + " D+",
                              ProtoMapFormat.grade(data.segment.grade)].joined(separator: " · ") + (data.segment.category.map { " · \($0)" } ?? ""))
                            .font(.subheadline).monospacedDigit()
                    }
                }
                ElevationProfileChart(profile: data.profile).frame(height: 100)
                if fiche.isFresh { ProtoFreshBanner() }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    tile("Mon record", symbol: "trophy.fill") {
                        if let best = data.myBest {
                            HStack(spacing: 6) {
                                Text(ProtoFicheData.time(best.seconds)).font(.title2.bold()).monospacedDigit()
                                if let medal = best.medal { ProtoMedal(place: medal, size: 18) }
                            }
                        } else { Text("—").font(.title2.bold()) }
                    }
                    tile("Mon rang", symbol: "list.number") {
                        if let me = all.me {
                            Text("\(me.rank)e").font(.title2.bold()).monospacedDigit()
                            + Text(" / \(all.rows.count)").font(.subheadline).foregroundStyle(.secondary)
                        } else { Text("—").font(.title2.bold()) }
                    }
                    tile("Légende locale", symbol: "laurel.leading") {
                        if let legend = data.legend(sex: .all) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(legend.rider.isMe ? "Toi" : legend.rider.name).font(.headline).lineLimit(1)
                                Text("\(legend.count) Efforts / 90 j · toi \(data.myRecentCount)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    NavigationLink(value: ProtoMapRoute.myEfforts(data.segment.id)) {
                        tile("Mes efforts", symbol: "clock.arrow.circlepath", chevron: true) {
                            Text("\(data.myEfforts.count)").font(.title2.bold())
                        }
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Classement").font(.title3.bold())
                    podium(all)
                    NavigationLink(value: ProtoMapRoute.leaderboard(data.segment.id)) {
                        HStack {
                            Text("Voir le classement")
                            if !fiche.isPremium { Text("· top 10").foregroundStyle(.secondary) }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary)
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(12)
                        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Theme.spacing)
            .padding(.bottom, 80)
        }
        .navigationTitle("Segment")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(ProtoFicheToolbar(store: store, fiche: fiche, data: data))
    }

    private func tile(_ title: String, symbol: String, chevron: Bool = false, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: symbol).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if chevron { Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary) }
            }
            content()
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
    }

    private func podium(_ board: ProtoBoard) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach([1, 0, 2], id: \.self) { index in
                if index < board.rows.count {
                    let row = board.rows[index]
                    VStack(spacing: 4) {
                        AvatarView(name: row.rider.name, url: nil, size: index == 0 ? 48 : 38)
                        Text(row.rider.name).font(.caption).lineLimit(1)
                        Text(ProtoFicheData.time(row.seconds)).font(.footnote.bold()).monospacedDigit()
                        Text("\(row.rank)").font(.headline).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: index == 0 ? 54 : (index == 1 ? 40 : 30))
                            .background(Theme.accent.opacity(index == 0 ? 1 : 0.7), in: .rect(cornerRadius: 8))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - Écran Classement (poussé)

struct ProtoLeaderboardScreen: View {
    let store: ProtoMapStore
    let fiche: ProtoFicheState
    let id: Int

    @State private var sex = ProtoSexFilter.all
    @State private var other = ProtoOtherFilter.none

    var body: some View {
        if let segment = store.segment(id) {
            let data = ProtoFicheData(segment: segment, hasEfforts: fiche.hasEfforts)
            let board = data.board(sex: sex, other: other)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ProtoLegendCard(data: data, sex: sex)
                        .padding(12)
                        .background(Color.orange.opacity(0.08), in: .rect(cornerRadius: 12))
                    ProtoBoardList(fiche: fiche, board: board, pinsMe: false)
                }
                .padding(Theme.spacing)
                .padding(.bottom, 80)
            }
            .safeAreaInset(edge: .top) { chips.background(.bar) }
            .safeAreaInset(edge: .bottom) {
                if let me = board.me {
                    ProtoBoardRowView(row: me).padding(.horizontal, Theme.spacing).padding(.vertical, 6).background(.bar)
                } else if !data.myEfforts.isEmpty {
                    Text("Tu n'apparais pas dans ce filtre.").font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(10).background(.bar)
                }
            }
            .padding(.bottom, 50)
            .navigationTitle("Classement")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: fiche.isPremium) { if !fiche.isPremium { sex = .all; other = .none } }
        }
    }

    /// Une rangée de puces : le sexe, puis un seul autre filtre (un toucher le remplace).
    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ProtoSexFilter.allCases) { option in
                    chip(option.rawValue, on: sex == option, locked: option != .all) { sex = option }
                }
                Divider().frame(height: 24)
                ForEach(ProtoOtherFilter.periods + [.following], id: \.self) { filter in
                    chip(filter.label, on: other == filter, locked: true) { other = other == filter ? .none : filter }
                }
                bandMenu("Âge", bands: ProtoOtherFilter.ageBands.map(\.0)) { ProtoOtherFilter.age($0) }
                bandMenu("Poids", bands: ProtoOtherFilter.weightBands.map(\.0)) { ProtoOtherFilter.weight($0) }
            }
            .padding(.horizontal, Theme.spacing)
            .padding(.vertical, 8)
        }
    }

    private func chip(_ title: String, on: Bool, locked: Bool, action: @escaping () -> Void) -> some View {
        let isLocked = locked && !fiche.isPremium
        return ProtoChip(title: title, symbol: isLocked ? "lock.fill" : nil, isOn: on) {
            if isLocked { fiche.locked("leaderboard_filter") } else { action() }
        }
    }

    @ViewBuilder
    private func bandMenu(_ title: String, bands: [String], filter: @escaping (Int) -> ProtoOtherFilter) -> some View {
        let selected = bands.indices.first { other == filter($0) }
        if fiche.isPremium {
            Menu {
                ForEach(bands.indices, id: \.self) { index in
                    Button(bands[index]) { other = filter(index) }
                }
                if selected != nil { Button("Retirer", role: .destructive) { other = .none } }
            } label: {
                ProtoChip(title: selected.map { bands[$0] } ?? "\(title) ▾", isOn: selected != nil) {}
                    .allowsHitTesting(false)
            }
        } else {
            chip(title, on: false, locked: true) {}
        }
    }
}

// MARK: - Écran Mes efforts (poussé)

struct ProtoMyEffortsScreen: View {
    let store: ProtoMapStore
    let fiche: ProtoFicheState
    let id: Int

    var body: some View {
        if let segment = store.segment(id) {
            let data = ProtoFicheData(segment: segment, hasEfforts: fiche.hasEfforts)
            let rankInAll = data.board(sex: .all, other: .none).me?.rank
            List {
                if data.myEfforts.isEmpty {
                    ProtoNoEffort()
                } else {
                    Section { ProtoMyRecordRow(data: data, rankInAll: rankInAll) }
                    Section("Tous mes passages") {
                        ForEach(data.myEfforts.reversed()) { ProtoMyEffortRow(effort: $0, rank: rankInAll) }
                    }
                }
            }
            .navigationTitle("Mes efforts")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
#endif
