#if DEBUG
import Charts
import SwiftUI

// PROTOTYPE — throwaway (voir ProfileRecordsProto.swift). Écrans poussés et briques communes.

// MARK: - Briques

struct ProtoRecordSportPills: View {
    let sports: [ProtoRecordSport]
    @Binding var selection: ProtoRecordSport

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sports) { sport in
                    let isOn = sport == selection
                    Button { selection = sport } label: {
                        Label(sport.rawValue, systemImage: sport.symbol)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .foregroundStyle(isOn ? .white : .primary)
                            .background(isOn ? Theme.accent : Color(.secondarySystemGroupedBackground), in: Capsule())
                            .overlay(Capsule().strokeBorder(isOn ? .clear : Color(.systemGray4)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.spacing)
        }
    }
}

struct ProtoProfileCard<Content: View>: View {
    let title: String
    var action: (String, ProtoProfileRoute)?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if let action {
                    NavigationLink(value: action.1) {
                        Text(action.0).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                    }
                }
            }
            content()
        }
        .padding(Theme.spacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }
}

/// Une distance : médaille PR, distance, temps et date du Record.
struct ProtoRecordRow: View {
    let record: ProtoDistanceRecord
    var showsActivity = true

    var body: some View {
        HStack(spacing: 12) {
            ProtoMedal(place: 1, size: 26)
                .opacity(record.isFresh ? 1 : 0.35)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.label).font(.body.weight(.semibold))
                Text(showsActivity ? "\(ProtoProfileFormat.date(record.best.date)) · \(record.best.activity)" : ProtoProfileFormat.date(record.best.date))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(ProtoProfileFormat.time(record.best.seconds))
                .font(.body.weight(.semibold)).monospacedDigit()
        }
        .contentShape(.rect)
    }
}

struct ProtoSegmentRow: View {
    let segment: ProtoMapSegment
    var trailing: String?
    var detail: String?
    var medal: Int?
    var crown = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: segment.sport.symbol)
                .font(.title3).frame(width: 30).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(segment.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if segment.isVerified {
                        Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(.blue)
                    }
                }
                Text(detail ?? "\(ProtoProfileFormat.distance(segment.meters)) · \(ProtoProfileFormat.grade(segment.grade))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if crown { ProtoCrown(size: 24) }
            if let medal { ProtoMedal(place: medal, size: 24) }
            if let trailing {
                Text(trailing).font(.subheadline.weight(.semibold)).monospacedDigit()
            }
        }
        .contentShape(.rect)
    }
}

/// La couronne de laurier du Local Legend.
struct ProtoCrown: View {
    var size: CGFloat = 22
    var body: some View {
        HStack(spacing: -size * 0.2) {
            Image(systemName: "laurel.leading")
            Image(systemName: "laurel.trailing")
        }
        .font(.system(size: size * 0.8, weight: .semibold))
        .foregroundStyle(Color(red: 0.55, green: 0.35, blue: 0.85))
        .accessibilityLabel("Légende locale")
    }
}

struct ProtoEmptyLine: View {
    let text: String
    var body: some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Meilleurs efforts : liste par sport

struct ProtoBestEffortsScreen: View {
    let state: ProtoProfileState
    let mine: Bool
    @State private var sport: ProtoRecordSport

    init(state: ProtoProfileState, mine: Bool, initialSport: ProtoRecordSport?) {
        self.state = state
        self.mine = mine
        _sport = State(initialValue: initialSport ?? state.recordSports(mine: mine).first ?? .run)
    }

    var body: some View {
        let sports = state.recordSports(mine: mine)
        List {
            if sports.isEmpty {
                ProtoEmptyLine(text: mine
                    ? "Pas encore de meilleur effort. Ils se calculent tout seuls sur tes Activités avec une trace GPS (ou les longueurs d'une piscine)."
                    : "Léa ne montre pas ses meilleurs efforts.")
            } else {
                Section {
                    ProtoRecordSportPills(sports: sports, selection: $sport)
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
                Section {
                    ForEach(state.records(mine: mine, sport: sport)) { record in
                        NavigationLink(value: ProtoProfileRoute.distance(mine: mine, sport: sport, label: record.label)) {
                            ProtoRecordRow(record: record)
                        }
                    }
                } footer: {
                    footer
                }
            }
        }
        .navigationTitle("Meilleurs efforts")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var footer: some View {
        if sport == .pool {
            Text("Bassins de 25 et 50 m, depuis un fichier FIT. Pas de meilleur effort en yards.")
        } else if !mine && state.othersRecords == .visibleOnly {
            Text("Seulement les temps des Activités de Léa que tu peux voir.")
        } else if mine {
            Text("Calculés sur toutes tes Activités, même privées. Médaille pâle : record de plus de 30 jours.")
        }
    }
}

// MARK: - Une distance : podium, progression, tous les temps

struct ProtoDistanceScreen: View {
    let state: ProtoProfileState
    let mine: Bool
    let sport: ProtoRecordSport
    let label: String
    @State private var removing: ProtoEffortTime?

    var body: some View {
        Group {
            if let record = state.record(mine: mine, sport: sport, label: label) {
                content(record)
            } else {
                ContentUnavailableView("Plus de temps sur \(label)", systemImage: "medal")
            }
        }
        .navigationTitle("\(label) · \(sport.rawValue)")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Retirer ce temps de tes meilleurs efforts ?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible,
            presenting: removing
        ) { time in
            Button("Retirer ce temps", role: .destructive) { state.remove(time, label: label) }
        } message: { _ in
            Text("C'est définitif : il ne reviendra pas, même après un recalcul. L'Activité ne change pas.")
        }
    }

    private func content(_ record: ProtoDistanceRecord) -> some View {
        List {
            Section {
                VStack(spacing: 6) {
                    ProtoMedal(place: 1, size: 48)
                    Text(ProtoProfileFormat.time(record.best.seconds))
                        .font(.system(size: 44, weight: .bold)).monospacedDigit()
                    Text(sport.pace(seconds: record.best.seconds, meters: record.meters))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("Record personnel · \(ProtoProfileFormat.date(record.best.date))")
                        .font(.subheadline)
                    Button("Voir l'Activité « \(record.best.activity) »") { state.say("Ouvre le détail de l'Activité (#239)") }
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            if record.times.count > 1 {
                Section("Progression") {
                    Chart(record.times.sorted { $0.date < $1.date }) { time in
                        LineMark(x: .value("Date", time.date), y: .value("Temps", time.seconds))
                            .foregroundStyle(Color(.systemGray3))
                        PointMark(x: .value("Date", time.date), y: .value("Temps", time.seconds))
                            .foregroundStyle(record.medal(of: time) == nil ? Color(.systemGray) : Theme.accent)
                    }
                    .chartYScale(domain: .automatic(includesZero: false, reversed: true))
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel { if let seconds = value.as(Int.self) { Text(ProtoProfileFormat.time(seconds)) } }
                        }
                    }
                    .frame(height: 160)
                }
            }
            Section("Podium") {
                ForEach(record.podium) { time in row(time, record: record, medal: record.medal(of: time)) }
            }
            Section {
                ForEach(record.byDate) { time in row(time, record: record, medal: record.medal(of: time)) }
            } header: {
                Text("Tous les temps (\(record.times.count))")
            } footer: {
                if mine { Text("Glisse un temps vers la gauche pour le retirer (GPS faux, trajet en voiture…).") }
            }
        }
    }

    private func row(_ time: ProtoEffortTime, record: ProtoDistanceRecord, medal: Int?) -> some View {
        HStack(spacing: 12) {
            if let medal { ProtoMedal(place: medal, size: 24) } else { Color.clear.frame(width: 24, height: 24) }
            VStack(alignment: .leading, spacing: 2) {
                Text(time.activity).font(.subheadline.weight(.semibold))
                HStack(spacing: 4) {
                    Text(ProtoProfileFormat.date(time.date))
                    if mine && time.visibility != .public {
                        Image(systemName: time.visibility == .private ? "lock.fill" : "person.2.fill")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(ProtoProfileFormat.time(time.seconds)).font(.subheadline.weight(.semibold)).monospacedDigit()
                Text(sport.pace(seconds: time.seconds, meters: record.meters)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .swipeActions {
            if mine {
                Button("Retirer", systemImage: "minus.circle") { removing = time }.tint(.red)
            }
        }
        .contextMenu {
            if mine {
                Button("Retirer ce temps de mes meilleurs efforts", systemImage: "minus.circle", role: .destructive) { removing = time }
            }
        }
    }
}

// MARK: - Segments : favoris, Légende locale, récents

enum ProtoSegmentsTab: String, CaseIterable, Hashable {
    case favorites = "Favoris", legends = "Légende locale", recent = "Récents"
}

struct ProtoProfileSegmentsScreen: View {
    let state: ProtoProfileState
    let mine: Bool
    @State private var tab: ProtoSegmentsTab

    init(state: ProtoProfileState, mine: Bool, initialTab: ProtoSegmentsTab) {
        self.state = state
        self.mine = mine
        _tab = State(initialValue: initialTab)
    }

    private var tabs: [ProtoSegmentsTab] {
        mine || state.othersShowFavorites ? ProtoSegmentsTab.allCases : [.legends, .recent]
    }

    var body: some View {
        List {
            Section {
                Picker("Segments", selection: $tab) {
                    ForEach(tabs, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            Section {
                switch tab {
                case .favorites: favorites
                case .legends: legends
                case .recent: recent
                }
            } footer: {
                footer
            }
        }
        .navigationTitle("Segments")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var favorites: some View {
        let segments = state.favorites(mine: mine)
        if segments.isEmpty {
            ProtoEmptyLine(text: "Touche l'étoile d'un Segment pour le retrouver ici.")
        }
        ForEach(segments) { segment in
            NavigationLink(value: ProtoMapRoute.segment(segment.id)) {
                ProtoSegmentRow(segment: segment, trailing: segment.myBest)
            }
        }
    }

    @ViewBuilder private var legends: some View {
        let legends = state.legends(mine: mine)
        if legends.isEmpty {
            ProtoEmptyLine(text: mine ? "Fais le plus de passages sur un Segment en 90 jours pour devenir Légende locale." : "Léa n'est Légende locale d'aucun Segment.")
        }
        ForEach(legends) { legend in
            if let segment = state.segment(legend.segmentID) {
                NavigationLink(value: ProtoMapRoute.segment(segment.id)) {
                    ProtoSegmentRow(segment: segment, trailing: "\(legend.count)", detail: "\(legend.count) efforts en 90 jours", crown: true)
                }
            }
        }
    }

    @ViewBuilder private var recent: some View {
        let efforts = state.recentEfforts(mine: mine)
        if efforts.isEmpty { ProtoEmptyLine(text: "Aucun passage sur un Segment pour l'instant.") }
        ForEach(efforts) { effort in
            if let segment = state.segment(effort.segmentID) {
                NavigationLink(value: ProtoMapRoute.segment(segment.id)) {
                    ProtoSegmentRow(
                        segment: segment,
                        trailing: ProtoProfileFormat.time(effort.seconds),
                        detail: "\(ProtoProfileFormat.ago(effort.daysAgo)) · \(ProtoProfileFormat.distance(segment.meters))",
                        medal: effort.medal
                    )
                }
            }
        }
    }

    @ViewBuilder private var footer: some View {
        switch tab {
        case .legends: Text("Le plus de passages sur 90 jours glissants. Une Activité compte une fois.")
        case .recent where !mine: Text("Seulement ses Activités que tu peux voir.")
        default: EmptyView()
        }
    }
}

// MARK: - Mes Segments (décidé au prototype #236)

struct ProtoMySegmentsScreen: View {
    let state: ProtoProfileState

    var body: some View {
        List {
            if state.mySegments.isEmpty {
                ProtoEmptyLine(text: "Dessine un Segment sur la carte avec le « + ».")
            }
            ForEach(state.mySegments) { segment in
                HStack(spacing: 12) {
                    Image(systemName: segment.sport.symbol).font(.title3).frame(width: 30).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(segment.name).font(.subheadline.weight(.semibold))
                        Text([ProtoProfileFormat.distance(segment.meters), ProtoProfileFormat.grade(segment.grade), segment.category].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let athletes = segment.athletes {
                        Text("\(athletes) athlètes").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Recherche des passages…").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button("Supprimer", role: .destructive) { state.say("Refusé : d'autres athlètes ont un Effort (#230)") }
                    Button("Renommer") { state.say("Renommer (#236)") }
                }
            }
        }
        .navigationTitle("Mes Segments")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Créer un Segment", systemImage: "plus") { state.say("Ouvre le dessin d'un Segment (#236)") }
        }
    }
}
#endif
