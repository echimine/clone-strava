#if DEBUG
import SwiftUI

// PROTOTYPE — throwaway (voir ProfileRecordsProto.swift). Les trois variantes.

// MARK: - A — Comme Strava : des lignes dans « Plus »

struct ProtoProfileMoreA: View {
    let state: ProtoProfileState
    let mine: Bool

    var body: some View {
        VStack(spacing: 0) {
            Button { state.say("Statistiques (existant)") } label: {
                ProfileMenuRow(title: "Statistiques", subtitle: "Cette année : 4 212,6 km", systemImage: "list.bullet.rectangle")
            }
            .buttonStyle(.plain)
            NavigationLink(value: ProtoProfileRoute.bestEfforts(mine: mine, sport: nil)) {
                ProfileMenuRow(title: "Meilleurs efforts", subtitle: bestEffortsSubtitle, systemImage: "stopwatch")
            }
            .buttonStyle(.plain)
            NavigationLink(value: ProtoProfileRoute.segments(mine: mine, tab: mine ? .favorites : .legends)) {
                ProfileMenuRow(title: "Segments", subtitle: segmentsSubtitle, systemImage: "point.bottomleft.forward.to.point.topright.scurvepath")
            }
            .buttonStyle(.plain)
            if mine {
                NavigationLink(value: ProtoProfileRoute.mySegments) {
                    ProfileMenuRow(title: "Mes Segments", subtitle: state.mySegments.isEmpty ? nil : "\(state.mySegments.count) Segments créés", systemImage: "pencil.and.outline")
                }
                .buttonStyle(.plain)
                Button { state.say("Mes Itinéraires (existant)") } label: {
                    ProfileMenuRow(title: "Itinéraires", subtitle: "3", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
    }

    private var bestEffortsSubtitle: String? {
        let run = state.records(mine: mine, sport: .run)
        let picks = run.filter { ["5 km", "10 km"].contains($0.label) }
        if !picks.isEmpty {
            return picks.map { "\($0.label) en \(ProtoProfileFormat.time($0.best.seconds))" }.joined(separator: " · ")
        }
        let sports = state.recordSports(mine: mine)
        return sports.isEmpty ? nil : sports.map(\.rawValue).joined(separator: ", ")
    }

    private var segmentsSubtitle: String? {
        var parts: [String] = []
        let favorites = state.favorites(mine: mine).count
        if favorites > 0 { parts.append("\(favorites) favoris") }
        let legends = state.legends(mine: mine).count
        if legends > 0 { parts.append("Légende locale sur \(legends) Segment\(legends > 1 ? "s" : "")") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - B — Dans « Progrès », sous la Série, filtrées par la puce de sport

struct ProtoProgressCardsB: View {
    let state: ProtoProfileState
    let mine: Bool
    let sport: SportType?

    var body: some View {
        let recordSports = ProtoRecordSport.allCases.filter { $0.sportType == sport }
        VStack(spacing: Theme.spacing) {
            ForEach(recordSports) { recordSport in
                bestEfforts(recordSport)
            }
            if let mapSport = ProtoMapSport.allCases.first(where: { $0.sportType == sport }) {
                segments(mapSport)
            }
        }
        .padding(.horizontal, Theme.spacing)
    }

    private func bestEfforts(_ recordSport: ProtoRecordSport) -> some View {
        let records = state.records(mine: mine, sport: recordSport)
        let title = recordSport.sportType == .swim ? "Meilleurs efforts · \(recordSport.rawValue)" : "Meilleurs efforts"
        return ProtoProfileCard(title: title, action: records.isEmpty ? nil : ("Tout voir", .bestEfforts(mine: mine, sport: recordSport))) {
            if records.isEmpty {
                ProtoEmptyLine(text: mine ? "Pas encore de meilleur effort dans ce sport." : "Rien à montrer.")
            } else {
                VStack(spacing: 10) {
                    ForEach(records) { record in
                        NavigationLink(value: ProtoProfileRoute.distance(mine: mine, sport: recordSport, label: record.label)) {
                            ProtoRecordRow(record: record, showsActivity: false)
                        }
                        .buttonStyle(.plain)
                        if record.id != records.last?.id { Divider() }
                    }
                }
            }
        }
    }

    @ViewBuilder private func segments(_ mapSport: ProtoMapSport) -> some View {
        let legends = state.legends(mine: mine).filter { state.segment($0.segmentID)?.sport == mapSport }
        let favorites = state.favorites(mine: mine).filter { $0.sport == mapSport }
        let recent = state.recentEfforts(mine: mine).filter { state.segment($0.segmentID)?.sport == mapSport }
        ProtoProfileCard(title: "Segments", action: ("Tout voir", .segments(mine: mine, tab: mine ? .favorites : .legends))) {
            VStack(alignment: .leading, spacing: 12) {
                if !legends.isEmpty {
                    NavigationLink(value: ProtoProfileRoute.segments(mine: mine, tab: .legends)) {
                        HStack(spacing: 10) {
                            ProtoCrown(size: 28)
                            Text("Légende locale sur \(legends.count) Segment\(legends.count > 1 ? "s" : "")").font(.subheadline.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(Color.purple.opacity(0.08), in: .rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                if !favorites.isEmpty {
                    Text("Favoris").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(favorites) { segment in
                                NavigationLink(value: ProtoMapRoute.segment(segment.id)) { favoriteTile(segment) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
                Text("Efforts récents").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                if recent.isEmpty { ProtoEmptyLine(text: "Aucun passage récent dans ce sport.") }
                ForEach(recent.prefix(3)) { effort in
                    if let segment = state.segment(effort.segmentID) {
                        NavigationLink(value: ProtoMapRoute.segment(segment.id)) {
                            ProtoSegmentRow(
                                segment: segment,
                                trailing: ProtoProfileFormat.time(effort.seconds),
                                detail: ProtoProfileFormat.ago(effort.daysAgo),
                                medal: effort.medal
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                if mine {
                    Divider()
                    NavigationLink(value: ProtoProfileRoute.mySegments) {
                        HStack {
                            Label("Mes Segments", systemImage: "pencil.and.outline").font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(state.mySegments.count)").foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func favoriteTile(_ segment: ProtoMapSegment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "star.fill").foregroundStyle(.orange)
                if segment.isVerified { Image(systemName: "checkmark.seal.fill").foregroundStyle(.blue) }
            }
            .font(.caption)
            Text(segment.name).font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            Text("\(ProtoProfileFormat.distance(segment.meters)) · \(ProtoProfileFormat.grade(segment.grade))").font(.caption).foregroundStyle(.secondary)
            Text(segment.myBest.map { "Mon record \($0)" } ?? "Pas encore de passage").font(.caption.weight(.semibold))
        }
        .padding(10)
        .frame(width: 160, height: 120, alignment: .topLeading)
        .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }
}

/// B chez un autre athlète (pas de Progrès) : « Plus » reprend les cartes avec ses puces de sport.
struct ProtoOthersMoreB: View {
    let state: ProtoProfileState
    @State private var sport: SportType?

    var body: some View {
        let sports = Array(Set(state.recordSports(mine: false).map(\.sportType) + [.run, .ride])).sorted { ActivityFormatters.sportLabel($0) < ActivityFormatters.sportLabel($1) }
        VStack(alignment: .leading, spacing: Theme.spacing) {
            Button { state.say("Statistiques (existant)") } label: {
                ProfileMenuRow(title: "Statistiques", subtitle: "Cette année : 1 102,4 km", systemImage: "list.bullet.rectangle")
            }
            .buttonStyle(.plain)
            .background(Color(.systemBackground))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sports, id: \.self) { item in
                        let isOn = item == (sport ?? sports.first)
                        Button { sport = item } label: {
                            Text(ActivityFormatters.sportLabel(item)).font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .foregroundStyle(isOn ? .white : .primary)
                                .background(isOn ? Theme.accent : Color(.secondarySystemGroupedBackground), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.spacing)
            }
            ProtoProgressCardsB(state: state, mine: false, sport: sport ?? sports.first)
        }
        .padding(.bottom, Theme.spacing)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - C — Un onglet « Résultats »

struct ProtoResultsTabC: View {
    let state: ProtoProfileState
    let mine: Bool
    @State private var sport: ProtoRecordSport?

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(spacing: Theme.spacing) {
            performances
            legends
            bestEfforts
            if !state.favorites(mine: mine).isEmpty { favorites }
            recent
            if mine {
                NavigationLink(value: ProtoProfileRoute.mySegments) {
                    ProtoProfileCard(title: "Mes Segments") {
                        HStack {
                            Text(state.mySegments.isEmpty ? "Dessine ton premier Segment" : "\(state.mySegments.count) Segments créés")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.spacing)
    }

    private var performances: some View {
        let medals = state.medals(mine: mine)
        return ProtoProfileCard(title: "Performances en 2026") {
            HStack {
                ForEach(0..<3) { index in
                    VStack(spacing: 4) {
                        ProtoMedal(place: index + 1, size: 40)
                        Text("\(medals[index])").font(.title3.weight(.bold)).monospacedDigit()
                        Text(["Records perso", "2es temps", "3es temps"][index]).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text("Médailles gagnées sur les Segments et les meilleurs efforts.").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var legends: some View {
        let legends = state.legends(mine: mine)
        if !legends.isEmpty {
            ProtoProfileCard(title: "Légende locale") {
                ForEach(legends) { legend in
                    if let segment = state.segment(legend.segmentID) {
                        NavigationLink(value: ProtoMapRoute.segment(segment.id)) {
                            ProtoSegmentRow(segment: segment, trailing: nil, detail: "\(legend.count) efforts en 90 jours", crown: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var bestEfforts: some View {
        let sports = state.recordSports(mine: mine)
        let current = sport.flatMap { sports.contains($0) ? $0 : nil } ?? sports.first
        return ProtoProfileCard(title: "Meilleurs efforts", action: current.map { ("Tout voir", .bestEfforts(mine: mine, sport: $0)) }) {
            if let current {
                ProtoRecordSportPills(sports: sports, selection: Binding(get: { current }, set: { sport = $0 }))
                    .padding(.horizontal, -Theme.spacing)
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(state.records(mine: mine, sport: current)) { record in
                        NavigationLink(value: ProtoProfileRoute.distance(mine: mine, sport: current, label: record.label)) {
                            tile(record)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                ProtoEmptyLine(text: mine ? "Tes meilleurs temps sur 5 km, 10 km, 40 km… apparaîtront ici." : "Léa ne montre pas ses meilleurs efforts.")
            }
        }
    }

    private func tile(_ record: ProtoDistanceRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.label).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
                if record.isFresh { ProtoMedal(place: 1, size: 22) }
            }
            Text(ProtoProfileFormat.time(record.best.seconds)).font(.title3.weight(.bold)).monospacedDigit()
            Text(ProtoProfileFormat.date(record.best.date)).font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }

    private var favorites: some View {
        ProtoProfileCard(title: "Segments favoris", action: ("Tout voir", .segments(mine: mine, tab: .favorites))) {
            ForEach(state.favorites(mine: mine).prefix(3)) { segment in
                NavigationLink(value: ProtoMapRoute.segment(segment.id)) {
                    ProtoSegmentRow(segment: segment, trailing: segment.myBest)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var recent: some View {
        let efforts = state.recentEfforts(mine: mine)
        return ProtoProfileCard(title: "Efforts récents", action: efforts.isEmpty ? nil : ("Tout voir", .segments(mine: mine, tab: .recent))) {
            if efforts.isEmpty { ProtoEmptyLine(text: "Aucun passage sur un Segment pour l'instant.") }
            ForEach(efforts.prefix(4)) { effort in
                if let segment = state.segment(effort.segmentID) {
                    NavigationLink(value: ProtoMapRoute.segment(segment.id)) {
                        ProtoSegmentRow(
                            segment: segment,
                            trailing: ProtoProfileFormat.time(effort.seconds),
                            detail: ProtoProfileFormat.ago(effort.daysAgo),
                            medal: effort.medal
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
#endif
