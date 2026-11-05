import SwiftUI

/// PROTOTYPE (#239): where the Results variants plug into `ActivityDetailContent`.
enum ProtoResultsSlot { case underHeader, underTitle, afterStats, afterEngagement, beforeSplits, replacement }

#if DEBUG
import MapboxMaps

// PROTOTYPE — throwaway. Ticket « Prototype : Segments et Records dans le détail d'une Activité »
// (#239), carte « Segments et Records dans l'app » (#223). Branche prototype/activity-results
// (partie de prototype/segment-detail), jamais fusionnée.
//
// Lancement : argument `-ActivityResultsPrototype` à la place de l'app : le vrai détail d'Activité
// (ActivityDetailPage, données en mémoire) d'une sortie vélo autour du lac d'Annecy qui passe sur
// 4 Segments du prototype de carte, avec 6 distances de Record. Option : `-protoResults A|B|C`.
// La pastille violette cycle les variantes ; son menu bascule le sport (vélo / natation en
// piscine), « mon Activité » ou celle d'une autre athlète, la visibilité, « sans résultat », et
// lance un appariement (5 s, puis `activity.segments_matched` arrive).
//   A — Section « Résultats » à la Strava sous les chiffres : compteurs, 3 lignes, « Afficher tous ».
//   B — Segments et Records séparés : ligne de Médailles sous le titre, Segments numérotés sur la
//       carte et en liste, Records en tableau juste avant les Splits.
//   C — Onglets Aperçu | Résultats sous la carte : tuiles, puces, toucher une ligne cadre le Segment.
// Un Segment touché ouvre la fiche du prototype #238 (variante A). Temps et rangs inventés.

enum ActivityResultsProto {
    static let launchArgument = "-ActivityResultsPrototype"
}

enum ProtoResultsRoute: Hashable { case all }

struct ProtoResults: @unchecked Sendable {
    let map: @MainActor (EncodedPolyline) -> AnyView?
    let view: @MainActor (ProtoResultsSlot) -> AnyView?
    let hidesOverview: @MainActor () -> Bool
}

extension EnvironmentValues {
    @Entry var protoResults: ProtoResults?
}

// MARK: - Données

struct ProtoSegmentResult: Identifiable {
    let id: Int
    let name: String
    let meters: Double
    let grade: Double
    let seconds: Int
    let medal: Int?
    let isFirstPass: Bool
    let rank: Int
    let athletes: Int
    /// Indices de la trace de l'Activité.
    var range: ClosedRange<Int> = 0...0
}

struct ProtoRecordResult: Identifiable {
    var id: String { label }
    let label: String
    let meters: Double
    let seconds: Int
    let medal: Int?
    let isFirstTime: Bool
}

enum ProtoResultsSport: String, CaseIterable { case ride = "Vélo", pool = "Natation en piscine" }

enum ProtoMedalText {
    static func label(_ medal: Int?) -> String? {
        switch medal {
        case 1: "Record personnel"
        case 2: "2e meilleur temps"
        case 3: "3e meilleur temps"
        default: nil
        }
    }

    /// Phrase d'un meilleur effort (Record), comme Strava.
    static func bestEffort(_ medal: Int?) -> String? {
        switch medal {
        case 1: "Nouveau record absolu !"
        case 2: "Nouveau 2e record absolu !"
        case 3: "Nouveau 3e record absolu !"
        default: nil
        }
    }

    static func rank(_ rank: Int, of athletes: Int) -> String {
        "\(rank.formatted(.number.locale(ActivityFormatters.locale)))e sur \(athletes.formatted(.number.locale(ActivityFormatters.locale)))"
    }
}

// MARK: - États basculés par la pastille

@MainActor @Observable
final class ProtoResultsState {
    var variant = UserDefaults.standard.string(forKey: "protoResults") ?? "A"
    var sport = ProtoResultsSport.ride
    var isMine = true
    var visibility = ActivityVisibility.public
    var hasResults = true
    var isMatching = false
    var removedRecords: Set<String> = []
    /// B et C : le Segment mis en avant sur la carte.
    var selected: Int?
    /// C : 0 Aperçu, 1 Résultats.
    var tab = 0
    var toast: String?
    var route: [Coordinate] = ProtoResultsSamples.fallbackRoute {
        didSet { allSegments = ProtoResultsSamples.segments(on: route) }
    }
    private(set) var allSegments = ProtoResultsSamples.segments(on: ProtoResultsSamples.fallbackRoute)
    var routeMessage: String? = "Chargement de la trace…"
    let activityID = ActivityID()

    /// Recharge la page quand ce que renvoie l'API change.
    var pageKey: String { "\(sport)-\(isMine)-\(visibility)-\(route.count)" }

    var showsRank: Bool { visibility == .public }

    var segments: [ProtoSegmentResult] {
        guard sport == .ride, hasResults, !isMatching else { return [] }
        return allSegments
    }

    var records: [ProtoRecordResult] {
        guard hasResults else { return [] }
        let all = sport == .ride ? ProtoResultsSamples.rideRecords : ProtoResultsSamples.poolRecords
        return all.filter { !removedRecords.contains($0.label) }
    }

    var medalCount: Int { segments.filter { $0.medal != nil }.count + records.filter { $0.medal != nil }.count }

    func medals(_ place: Int) -> Int {
        segments.filter { $0.medal == place }.count + records.filter { $0.medal == place }.count
    }

    var isEmpty: Bool { segments.isEmpty && records.isEmpty && !isMatching }

    /// Comme `activity.segments_matched` après le job `match-segments`.
    func simulateMatching() {
        isMatching = true
        Task {
            try? await Task.sleep(for: .seconds(5))
            withAnimation { isMatching = false }
            say("activity.segments_matched reçu : les Segments arrivent")
        }
    }

    func remove(_ record: ProtoRecordResult) {
        withAnimation { _ = removedRecords.insert(record.label) }
        say("\(record.label) : temps retiré de tes meilleurs efforts. Les médailles des autres temps sont recalculées.")
    }

    func say(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(for: .seconds(3))
            if toast == text { toast = nil }
        }
    }

    func makeStore(id: ActivityID) -> ActivityDetailStore {
        let repository = ProtoResultsRepository(detail: ProtoResultsSamples.detail(id: id, state: self))
        let changes = ActivityChanges()
        return ActivityDetailStore(
            id: id,
            loadDetail: LoadActivityDetail(repository: repository),
            loadKudos: LoadKudosList(repository: PreviewActivityKudosRepository()),
            setKudos: SetActivityKudos(repository: PreviewActivityKudosRepository()),
            changes: changes,
            updateActivity: UpdateActivity(repository: repository),
            deleter: ActivityDeleter(deleteActivity: DeleteActivity(repository: repository), changes: changes)
        )
    }

    func loadRoute(token: String) async {
        guard !token.isEmpty else { routeMessage = "Pas de jeton Mapbox : trace en ligne droite"; return }
        let points = ProtoResultsSamples.waypoints.map { "\($0.longitude),\($0.latitude)" }.joined(separator: ";")
        let url = URL(string: "https://api.mapbox.com/directions/v5/mapbox/cycling/\(points)?geometries=geojson&overview=full&access_token=\(token)")!
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let response = try? JSONDecoder().decode(ProtoDirections.self, from: data),
              let line = response.routes.first?.geometry.coordinates, line.count > 10 else {
            routeMessage = "Trace en ligne droite (réseau)"
            return
        }
        route = line.map { Coordinate(latitude: $0[1], longitude: $0[0]) }
        routeMessage = nil
    }

    func host() -> ProtoResults {
        ProtoResults(
            map: { [self] _ in sport == .ride ? AnyView(ProtoResultsMap(state: self)) : nil },
            view: { [self] slot in view(slot) },
            hidesOverview: { [self] in variant == "C" && tab == 1 }
        )
    }

    private func view(_ slot: ProtoResultsSlot) -> AnyView? {
        switch (variant, slot) {
        case ("A", .beforeSplits): AnyView(ProtoResultsVariantA(state: self))
        case ("B", .underTitle): AnyView(ProtoResultsBMedalLine(state: self))
        case ("B", .afterEngagement): AnyView(ProtoResultsBSegments(state: self))
        case ("B", .beforeSplits): AnyView(ProtoResultsBRecords(state: self))
        case ("C", .underHeader): AnyView(ProtoResultsCTabs(state: self))
        case ("C", .replacement): AnyView(ProtoResultsCList(state: self))
        default: nil
        }
    }
}

private struct ProtoDirections: Decodable {
    struct Route: Decodable {
        struct Geometry: Decodable { let coordinates: [[Double]] }
        let geometry: Geometry
    }
    let routes: [Route]
}

private struct ProtoResultsRepository: ActivityDetailRepository {
    let detail: ActivityDetail
    func detail(id: ActivityID) async throws(ActivityDetailError) -> ActivityDetail { detail }
    func update(id: ActivityID, with edit: ActivityEdit) async throws(ActivityDetailError) -> ActivityDetail { edit.applied(to: detail) }
    func delete(id: ActivityID) async throws(ActivityDetailError) {}
}

// MARK: - Racine : le vrai détail d'Activité

struct ActivityResultsPrototypeView: View {
    @State private var state = ProtoResultsState()
    @State private var mapStore = ProtoMapStore()
    @State private var fiche = ProtoFicheState()
    @Environment(\.mapboxAccessToken) private var token

    var body: some View {
        NavigationStack {
            ActivityDetailPage(
                request: ActivityDetailRequest(id: state.activityID),
                makeStore: { [state] id in state.makeStore(id: id) },
                liveEvents: PreviewActivityLiveEventSource()
            )
            .id(state.pageKey)
            .environment(\.protoResults, state.host())
            .navigationDestination(for: ProtoResultsRoute.self) { _ in ProtoAllResultsScreen(state: state) }
            .navigationDestination(for: ProtoMapRoute.self) { route in
                switch route {
                case .segment(let id): ProtoSegmentFiche(store: mapStore, fiche: fiche, id: id)
                case .leaderboard(let id): ProtoLeaderboardScreen(store: mapStore, fiche: fiche, id: id)
                case .myEfforts(let id): ProtoMyEffortsScreen(store: mapStore, fiche: fiche, id: id)
                case .explore: ProtoExploreScreen(store: mapStore)
                }
            }
        }
        .overlay(alignment: .bottom) { ProtoResultsBar(state: state).padding(.bottom, 8) }
        .overlay(alignment: .top) {
            VStack(spacing: 4) {
                if let message = state.routeMessage { ProtoResultsPill(text: message) }
                if let toast = state.toast { ProtoResultsPill(text: toast) }
            }
            .padding(.top, 2)
        }
        .sheet(isPresented: Binding(get: { fiche.paywallEntry != nil }, set: { if !$0 { fiche.paywallEntry = nil } })) {
            ProtoPaywallSheet(fiche: fiche)
        }
        .onChange(of: state.variant) { state.tab = 0; state.selected = nil }
        .task { await state.loadRoute(token: token) }
        .task { await mapStore.loadPaths(token: token) }
    }
}

struct ProtoResultsPill: View {
    let text: String
    var body: some View {
        Text(text).font(.caption2).multilineTextAlignment(.center)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
            .padding(.horizontal)
    }
}

// MARK: - Pastille violette : pas une partie du design évalué

struct ProtoResultsBar: View {
    @Bindable var state: ProtoResultsState
    static let variants = [("A", "Résultats comme Strava"), ("B", "Segments et Records séparés"), ("C", "Onglet Résultats")]

    var body: some View {
        HStack(spacing: 4) {
            Button { cycle(-1) } label: { Image(systemName: "chevron.left").frame(width: 30, height: 30) }
            VStack(spacing: 0) {
                Text("Résultats \(state.variant)").font(.caption.weight(.bold))
                Text(Self.variants.first { $0.0 == state.variant }?.1 ?? "").font(.caption2)
            }
            .frame(minWidth: 160)
            Button { cycle(1) } label: { Image(systemName: "chevron.right").frame(width: 30, height: 30) }
            Menu {
                Picker("Sport", selection: $state.sport) {
                    ForEach(ProtoResultsSport.allCases, id: \.self) { Text($0.rawValue) }
                }
                Toggle("Mon Activité", isOn: Binding(get: { state.isMine }, set: { mine in
                    state.isMine = mine
                    if !mine, state.visibility == .private { state.visibility = .followers }
                }))
                Picker("Visibilité", selection: $state.visibility) {
                    Text("Public").tag(ActivityVisibility.public)
                    Text("Abonnés").tag(ActivityVisibility.followers)
                    if state.isMine { Text("Privée").tag(ActivityVisibility.private) }
                }
                Toggle("Sans résultat", isOn: Binding(get: { !state.hasResults }, set: { state.hasResults = !$0 }))
                Button("Appariement en cours (5 s)", systemImage: "arrow.triangle.2.circlepath") { state.simulateMatching() }
                if !state.removedRecords.isEmpty {
                    Button("Remettre les temps retirés") { state.removedRecords = [] }
                }
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
        let index = keys.firstIndex(of: state.variant) ?? 0
        state.variant = keys[(index + step + keys.count) % keys.count]
    }
}
#endif
