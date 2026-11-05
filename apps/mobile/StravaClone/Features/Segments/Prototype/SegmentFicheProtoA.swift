#if DEBUG
import SwiftUI

// PROTOTYPE — throwaway (voir SegmentFicheProto.swift).
// Variante A — « Tout sur une page », proche de Strava : une seule page qui défile. Carte en tête,
// nom et chiffres, profil d'altitude, Mes efforts, Légende locale, puis le Classement avec le
// sélecteur de sexe et un menu « un autre filtre ».

struct ProtoFicheVariantA: View {
    let store: ProtoMapStore
    let fiche: ProtoFicheState
    let data: ProtoFicheData

    @State private var sex = ProtoSexFilter.all
    @State private var other = ProtoOtherFilter.none

    var body: some View {
        let board = data.board(sex: sex, other: other)
        let rankInAll = data.board(sex: .all, other: .none).me?.rank
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ProtoFicheMap(segment: data.segment).frame(height: 230)

                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(data.segment.name).font(.title2.bold())
                        ProtoSportLine(segment: data.segment)
                    }
                    ProtoFacts(data: data)
                    ElevationProfileChart(profile: data.profile).frame(height: 120)

                    if fiche.isFresh { ProtoFreshBanner() }

                    section("Mes efforts") {
                        if data.myEfforts.isEmpty {
                            ProtoNoEffort()
                        } else {
                            ProtoMyRecordRow(data: data, rankInAll: rankInAll)
                            Divider()
                            ForEach(data.myEfforts.reversed()) { effort in
                                ProtoMyEffortRow(effort: effort, rank: rankInAll)
                            }
                        }
                    }

                    section("Légende locale") {
                        ProtoLegendCard(data: data, sex: sex)
                    }

                    section("Classement") {
                        HStack(spacing: 8) {
                            ProtoSexPicker(fiche: fiche, sex: $sex)
                            ProtoOtherFilterMenu(fiche: fiche, other: $other)
                        }
                        if other != .none || sex != .all {
                            Text("\(board.rows.count) athlètes · \(sex.rawValue)\(other == .none ? "" : ", \(other.label.lowercased())")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if board.me == nil, !data.myEfforts.isEmpty {
                            Text("Tu n'apparais pas dans ce filtre.").font(.caption).foregroundStyle(.secondary)
                        }
                        ProtoBoardList(fiche: fiche, board: board)
                    }
                }
                .padding(Theme.spacing)
                .padding(.bottom, 80)
            }
        }
        .navigationTitle(data.segment.name)
        .navigationBarTitleDisplayMode(.inline)
        .modifier(ProtoFicheToolbar(store: store, fiche: fiche, data: data))
        .onChange(of: fiche.isPremium) { if !fiche.isPremium { sex = .all; other = .none } }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.bold())
            content()
        }
    }
}
#endif
