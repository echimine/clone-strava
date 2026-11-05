#if DEBUG
import SwiftUI

// PROTOTYPE — throwaway (voir SegmentFicheProto.swift).
// Variante B — « Carte + panneau à onglets » : la carte du Segment remplit l'écran (on peut s'y
// déplacer) ; un panneau qu'on tire vers le haut porte le nom et les chiffres, puis trois onglets :
// Aperçu (profil, Légende locale), Mes efforts, Classement (sélecteur de sexe + menu de filtre).

struct ProtoFicheVariantB: View {
    let store: ProtoMapStore
    let fiche: ProtoFicheState
    let data: ProtoFicheData

    private enum Tab: String, CaseIterable { case overview = "Aperçu", mine = "Mes efforts", board = "Classement" }
    private enum Detent { case peek, middle, full }

    @State private var tab = Tab.overview
    @State private var detent = Detent.middle
    @State private var drag: CGFloat = 0
    @State private var sex = ProtoSexFilter.all
    @State private var other = ProtoOtherFilter.none

    var body: some View {
        GeometryReader { geometry in
            let height = panelHeight(in: geometry.size.height)
            ZStack(alignment: .bottom) {
                ProtoFicheMap(segment: data.segment, top: 60, bottom: geometry.size.height * 0.45, interactive: true)
                    .ignoresSafeArea()
                panel
                    .frame(height: max(height - drag, 140))
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemBackground), in: UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))
                    .shadow(color: .black.opacity(0.15), radius: 10, y: -2)
                    .gesture(
                        DragGesture()
                            .onChanged { drag = $0.translation.height }
                            .onEnded { value in
                                withAnimation(.snappy) {
                                    let target = height - value.predictedEndTranslation.height
                                    let options: [(Detent, CGFloat)] = [.peek, .middle, .full].map { ($0, panelHeight(for: $0, in: geometry.size.height)) }
                                    detent = options.min { abs($0.1 - target) < abs($1.1 - target) }!.0
                                    drag = 0
                                }
                            }
                    )
            }
        }
        .navigationTitle(detent == .full ? data.segment.name : "")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(ProtoFicheToolbar(store: store, fiche: fiche, data: data))
        .onChange(of: fiche.isPremium) { if !fiche.isPremium { sex = .all; other = .none } }
    }

    private func panelHeight(in total: CGFloat) -> CGFloat { panelHeight(for: detent, in: total) }

    private func panelHeight(for detent: Detent, in total: CGFloat) -> CGFloat {
        switch detent {
        case .peek: 190
        case .middle: total * 0.55
        case .full: total - 20
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color(.tertiaryLabel)).frame(width: 40, height: 5).padding(.vertical, 8)
            VStack(alignment: .leading, spacing: 10) {
                Text(data.segment.name).font(.title3.bold()).lineLimit(1)
                ProtoSportLine(segment: data.segment)
                ProtoFacts(data: data)
                Picker("Onglet", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: tab) { if detent == .peek { withAnimation(.snappy) { detent = .middle } } }
            }
            .padding(.horizontal, Theme.spacing)
            .contentShape(Rectangle())

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if fiche.isFresh { ProtoFreshBanner() }
                    switch tab {
                    case .overview: overview
                    case .mine: mine
                    case .board: leaderboard
                    }
                }
                .padding(Theme.spacing)
                .padding(.bottom, 80)
            }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 16) {
            ElevationProfileChart(profile: data.profile).frame(height: 120)
            ProtoLegendCard(data: data, sex: .all)
                .padding(12)
                .background(Color.orange.opacity(0.08), in: .rect(cornerRadius: 12))
            if let best = data.myBest {
                Button { tab = .mine } label: {
                    HStack {
                        Text("Mon record")
                        Spacer()
                        Text(ProtoFicheData.time(best.seconds)).bold().monospacedDigit()
                        Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var mine: some View {
        let rankInAll = data.board(sex: .all, other: .none).me?.rank
        if data.myEfforts.isEmpty {
            ProtoNoEffort()
        } else {
            ProtoMyRecordRow(data: data, rankInAll: rankInAll)
            Divider()
            ForEach(data.myEfforts.reversed()) { ProtoMyEffortRow(effort: $0, rank: rankInAll) }
        }
    }

    private var leaderboard: some View {
        let board = data.board(sex: sex, other: other)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ProtoSexPicker(fiche: fiche, sex: $sex)
                ProtoOtherFilterMenu(fiche: fiche, other: $other)
            }
            if board.me == nil, !data.myEfforts.isEmpty {
                Text("Tu n'apparais pas dans ce filtre.").font(.caption).foregroundStyle(.secondary)
            }
            ProtoBoardList(fiche: fiche, board: board)
        }
    }
}
#endif
