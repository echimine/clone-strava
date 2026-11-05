import SwiftUI

/// PROTOTYPE (#240): where the profile variants plug into `ProfileView` and `AthleteProfilePage`.
enum ProtoProfileSlot { case progressEnd, more, results }

#if DEBUG

// PROTOTYPE — throwaway. Ticket « Prototype : Records et Segments dans le profil » (#240), carte
// « Segments et Records dans l'app » (#223). Branche prototype/profile-records (partie de
// prototype/activity-results), jamais fusionnée.
//
// Lancement : argument `-ProfileRecordsPrototype` à la place de l'app : le vrai onglet Profil
// (ProfileView, données en mémoire) d'Eliott, ou le vrai profil d'une autre athlète
// (AthleteProfilePage, Léa). Options : `-protoProfile A|B|C`, `-protoOther YES`.
// La pastille violette cycle les variantes ; son menu bascule mon profil / celui de Léa, ce que
// Léa montre de ses meilleurs efforts, ses favoris, un athlète tout neuf, et remet les temps retirés.
//   A — Comme Strava : des lignes dans « Plus » (Meilleurs efforts, Segments, Mes Segments) qui
//       poussent leurs écrans ; une distance pousse son podium, sa progression et tous ses temps.
//   B — Dans « Progrès » : cartes Meilleurs efforts et Segments sous la Série, filtrées par la
//       puce de sport de l'onglet (chez les autres, dans « Plus », avec leurs puces).
//   C — Un onglet « Résultats » : Performances (médailles), Légende locale, tuiles de meilleurs
//       efforts, favoris, efforts récents, Mes Segments.
// Un Segment touché ouvre la fiche du prototype #238. Temps, dates et Activités inventés.

enum ProfileRecordsProto {
    static let launchArgument = "-ProfileRecordsPrototype"
}

enum ProtoProfileRoute: Hashable {
    case bestEfforts(mine: Bool, sport: ProtoRecordSport?)
    case distance(mine: Bool, sport: ProtoRecordSport, label: String)
    case segments(mine: Bool, tab: ProtoSegmentsTab)
    case mySegments
}

struct ProtoProfile: @unchecked Sendable {
    let view: @MainActor (ProtoProfileSlot, Bool) -> AnyView?
    let replaces: @MainActor (ProtoProfileSlot, Bool) -> Bool
    let showsResultsTab: @MainActor () -> Bool
    let destination: @MainActor (ProtoProfileRoute) -> AnyView
    let mapDestination: @MainActor (ProtoMapRoute) -> AnyView
}

extension EnvironmentValues {
    @Entry var protoProfile: ProtoProfile?
}

// MARK: - États basculés par la pastille

/// Ce que Léa (un autre athlète) montre de ses meilleurs efforts.
enum ProtoOthersRecords: String, CaseIterable {
    case visibleOnly = "Seulement ce que je peux voir"
    case all = "Toutes ses Activités"
    case hidden = "Rien (privé)"
}

@MainActor @Observable
final class ProtoProfileState {
    var variant = UserDefaults.standard.string(forKey: "protoProfile") ?? "A" {
        didSet { openDefaultTab() }
    }
    var isMine = !UserDefaults.standard.bool(forKey: "protoOther")
    var othersRecords = ProtoOthersRecords.visibleOnly
    var othersShowFavorites = false
    var isNewAthlete = false
    var removed: Set<UUID> = []
    var toast: String?

    let mapStore = ProtoMapStore()
    let fiche = ProtoFicheState()
    let profileStore = ProtoProfileFactory.profileStore()
    /// Le store du profil de Léa, gardé pour ouvrir le bon onglet.
    var athleteStore: AthleteProfileStore?

    var pageKey: String { "\(isMine)-\(isNewAthlete)" }

    // MARK: Données vues

    func records(mine: Bool, sport: ProtoRecordSport) -> [ProtoDistanceRecord] {
        if isNewAthlete { return [] }
        if !mine && othersRecords == .hidden { return [] }
        let all = mine ? ProtoProfileSamples.myRecords : ProtoProfileSamples.leaRecords
        return (all[sport] ?? []).compactMap { record in
            let times = record.times.filter { time in
                !removed.contains(time.id) && (mine || othersRecords == .all || time.visibility == .public)
            }
            return times.isEmpty ? nil : ProtoDistanceRecord(label: record.label, meters: record.meters, sport: sport, times: times)
        }
    }

    func recordSports(mine: Bool) -> [ProtoRecordSport] {
        ProtoRecordSport.allCases.filter { !records(mine: mine, sport: $0).isEmpty }
    }

    func record(mine: Bool, sport: ProtoRecordSport, label: String) -> ProtoDistanceRecord? {
        records(mine: mine, sport: sport).first { $0.label == label }
    }

    func favorites(mine: Bool) -> [ProtoMapSegment] {
        if isNewAthlete || (!mine && !othersShowFavorites) { return [] }
        let ids = mine ? ProtoProfileSamples.myFavoriteIDs : ProtoProfileSamples.leaFavoriteIDs
        return mapStore.segments.filter { mine ? $0.isStarred : ids.contains($0.id) }
    }

    func legends(mine: Bool) -> [ProtoLegend] {
        isNewAthlete ? [] : (mine ? ProtoProfileSamples.myLegends : ProtoProfileSamples.leaLegends)
    }

    func recentEfforts(mine: Bool) -> [ProtoRecentEffort] {
        isNewAthlete ? [] : (mine ? ProtoProfileSamples.myRecent : ProtoProfileSamples.leaRecent)
    }

    var mySegments: [ProtoCreatedSegment] { isNewAthlete ? [] : ProtoProfileSamples.mySegments }

    func medals(mine: Bool) -> [Int] { isNewAthlete ? [0, 0, 0] : (mine ? [23, 11, 9] : [8, 5, 6]) }

    func segment(_ id: Int) -> ProtoMapSegment? { mapStore.segment(id) }

    // MARK: Actions

    func remove(_ time: ProtoEffortTime, label: String) {
        withAnimation { _ = removed.insert(time.id) }
        say("\(label) : temps retiré de tes meilleurs efforts, pour toujours. Les médailles sont recalculées.")
    }

    func say(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(for: .seconds(3))
            if toast == text { toast = nil }
        }
    }

    func openDefaultTab() {
        switch variant {
        case "B":
            profileStore.tab = .progress
            athleteStore?.tab = .more
        case "C":
            profileStore.tab = .results
            athleteStore?.tab = .results
        default:
            profileStore.tab = .more
            athleteStore?.tab = .more
        }
    }

    // MARK: Branchement dans les vraies pages

    func host() -> ProtoProfile {
        ProtoProfile(
            view: { [self] slot, mine in view(slot, mine: mine) },
            replaces: { [self] slot, mine in slot == .more && (variant == "A" || (variant == "B" && !mine)) },
            showsResultsTab: { [self] in variant == "C" },
            destination: { [self] route in AnyView(ProtoProfileDestination(state: self, route: route)) },
            mapDestination: { [self] route in
                switch route {
                case .segment(let id): AnyView(ProtoSegmentFiche(store: mapStore, fiche: fiche, id: id))
                case .leaderboard(let id): AnyView(ProtoLeaderboardScreen(store: mapStore, fiche: fiche, id: id))
                case .myEfforts(let id): AnyView(ProtoMyEffortsScreen(store: mapStore, fiche: fiche, id: id))
                case .explore: AnyView(ProtoExploreScreen(store: mapStore))
                }
            }
        )
    }

    private func view(_ slot: ProtoProfileSlot, mine: Bool) -> AnyView? {
        switch (variant, slot, mine) {
        case ("A", .more, _): AnyView(ProtoProfileMoreA(state: self, mine: mine))
        case ("B", .progressEnd, true): AnyView(ProtoProgressCardsB(state: self, mine: true, sport: profileStore.progress.sport))
        case ("B", .more, false): AnyView(ProtoOthersMoreB(state: self))
        case ("C", .results, _): AnyView(ProtoResultsTabC(state: self, mine: mine))
        default: nil
        }
    }
}

/// Les écrans poussés depuis le profil, communs aux trois variantes.
struct ProtoProfileDestination: View {
    let state: ProtoProfileState
    let route: ProtoProfileRoute

    var body: some View {
        switch route {
        case .bestEfforts(let mine, let sport): ProtoBestEffortsScreen(state: state, mine: mine, initialSport: sport)
        case .distance(let mine, let sport, let label): ProtoDistanceScreen(state: state, mine: mine, sport: sport, label: label)
        case .segments(let mine, let tab): ProtoProfileSegmentsScreen(state: state, mine: mine, initialTab: tab)
        case .mySegments: ProtoMySegmentsScreen(state: state)
        }
    }
}

// MARK: - Racine : le vrai profil

struct ProfileRecordsPrototypeView: View {
    @State private var state = ProtoProfileState()
    @Environment(\.mapboxAccessToken) private var token

    var body: some View {
        Group {
            if state.isMine {
                ProfileView(
                    store: state.profileStore,
                    account: ProfileAccount(id: ProtoProfileFactory.myID, name: "Eliott C.", email: "eliott@example.com"),
                    signOut: {},
                    destinations: .none,
                    itineraries: { Text("Mes Itinéraires") },
                    search: { Text("Recherche") }
                )
            } else {
                NavigationStack {
                    AthleteProfilePage(
                        request: AthleteProfileRequest(id: ProtoProfileFactory.leaID),
                        makeStore: { [state] id in
                            let store = ProtoProfileFactory.athleteStore(id: id)
                            state.athleteStore = store
                            state.openDefaultTab()
                            return store
                        },
                        openActivity: { [state] _ in state.say("Ouvre le détail de l'Activité (#239)") },
                        openEngagement: { _ in }
                    )
                    .navigationDestination(for: ProtoProfileRoute.self) { ProtoProfileDestination(state: state, route: $0) }
                    .navigationDestination(for: ProtoMapRoute.self) { state.host().mapDestination($0) }
                }
            }
        }
        .id(state.pageKey)
        .environment(\.protoProfile, state.host())
        .overlay(alignment: .bottom) { ProtoProfileBar(state: state).padding(.bottom, 8) }
        .overlay(alignment: .top) {
            if let toast = state.toast ?? state.mapStore.pathsMessage { ProtoResultsPill(text: toast).padding(.top, 2) }
        }
        .sheet(isPresented: Binding(get: { state.fiche.paywallEntry != nil }, set: { if !$0 { state.fiche.paywallEntry = nil } })) {
            ProtoPaywallSheet(fiche: state.fiche)
        }
        .onAppear { state.openDefaultTab() }
        // `-protoPush best|distance|segments|recent|mine` : ouvre un écran poussé, pour les captures.
        .task {
            guard state.isMine, let push = UserDefaults.standard.string(forKey: "protoPush") else { return }
            try? await Task.sleep(for: .seconds(1))
            let route: ProtoProfileRoute? = switch push {
            case "best": .bestEfforts(mine: true, sport: nil)
            case "distance": .distance(mine: true, sport: .run, label: "10 km")
            case "segments": .segments(mine: true, tab: .favorites)
            case "recent": .segments(mine: true, tab: .recent)
            case "mine": .mySegments
            default: nil
            }
            if let route { state.profileStore.path.append(route) }
        }
        .task { await state.mapStore.loadPaths(token: token) }
    }
}

// MARK: - Pastille violette : pas une partie du design évalué

struct ProtoProfileBar: View {
    @Bindable var state: ProtoProfileState
    static let variants = [("A", "Lignes dans Plus (Strava)"), ("B", "Cartes dans Progrès"), ("C", "Onglet Résultats")]

    var body: some View {
        HStack(spacing: 4) {
            Button { cycle(-1) } label: { Image(systemName: "chevron.left").frame(width: 30, height: 30) }
            VStack(spacing: 0) {
                Text("Profil \(state.variant) · \(state.isMine ? "le mien" : "Léa")").font(.caption.weight(.bold))
                Text(Self.variants.first { $0.0 == state.variant }?.1 ?? "").font(.caption2)
            }
            .frame(minWidth: 170)
            Button { cycle(1) } label: { Image(systemName: "chevron.right").frame(width: 30, height: 30) }
            Menu {
                Picker("Profil", selection: $state.isMine) {
                    Text("Mon profil").tag(true)
                    Text("Profil de Léa (autre athlète)").tag(false)
                }
                Picker("Meilleurs efforts de Léa", selection: $state.othersRecords) {
                    ForEach(ProtoOthersRecords.allCases, id: \.self) { Text($0.rawValue) }
                }
                Toggle("Favoris de Léa visibles", isOn: $state.othersShowFavorites)
                Toggle("Athlète tout neuf (rien)", isOn: $state.isNewAthlete)
                if !state.removed.isEmpty {
                    Button("Remettre les temps retirés") { state.removed = [] }
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

// MARK: - Dépôts en mémoire

@MainActor
enum ProtoProfileFactory {
    nonisolated static let myID = "me"
    nonisolated static let leaID = "lea"

    static func profileStore() -> ProfileStore {
        let athletes = ProtoAthletes()
        let store = ProfileStore(
            loadProfile: LoadProfile(repository: athletes),
            loadYearToDateDistance: LoadYearToDateDistance(repository: ProtoStats()),
            loadEditableProfile: LoadEditableProfile(repository: ProtoProfiles()),
            updateProfile: UpdateProfile(repository: ProtoProfiles()),
            setApproveFollowers: SetApproveFollowers(repository: ProtoProfiles()),
            activities: ProfileActivitiesStore(loadActivities: LoadProfileActivities(repository: athletes)),
            progress: ProfileProgressStore(loadProgress: LoadProgress(repository: ProtoProgress())),
            gallery: AthleteGalleryStore(loadGallery: LoadAthleteGallery(repository: ProtoGallery()), message: ProfileMessages.message(for:)),
            avatar: .preview
        )
        return store
    }

    static func athleteStore(id: String) -> AthleteProfileStore {
        let athletes = ProtoAthletes()
        let follows = ProtoFollows()
        return AthleteProfileStore(
            athleteId: id,
            loadProfile: LoadAthleteProfile(repository: athletes),
            loadYearToDateDistance: LoadAthleteYearToDateDistance(repository: ProtoStats()),
            follows: FollowStore(followAthlete: FollowAthlete(repository: follows), unfollowAthlete: UnfollowAthlete(repository: follows)),
            activities: AthleteActivitiesStore(
                loadActivities: LoadAthleteActivities(repository: athletes),
                setKudos: SetAthleteActivityKudos(repository: ProtoKudos())
            ),
            gallery: AthleteGalleryStore(loadGallery: LoadAthleteGallery(repository: ProtoGallery()), message: AthletesMessages.message(for:))
        )
    }
}

private struct ProtoAthletes: AthleteRepository {
    func profile(of athleteId: String) async throws(AthleteError) -> AthleteProfile {
        let mine = athleteId == ProtoProfileFactory.myID
        return AthleteProfile(
            athlete: ActivityAuthor(id: athleteId, displayName: mine ? "Eliott C." : "Léa Bernard", avatarURL: nil),
            activityCount: mine ? 214 : 128,
            streakWeeks: mine ? 6 : 3,
            followerCount: mine ? 48 : 54,
            followingCount: mine ? 61 : 61,
            viewerFollowStatus: mine ? nil : .accepted,
            followersYouKnow: mine ? [] : [ActivityAuthor(id: "hugo", displayName: "Hugo Petit", avatarURL: nil)],
            practicedSports: mine ? [.ride, .run, .hike, .swim, .walk] : [.run, .ride],
            approveFollowers: mine ? false : nil,
            pendingFollowRequestCount: mine ? 0 : nil,
            itineraryCount: mine ? 3 : nil
        )
    }

    func activities(of athleteId: String, cursor: String?) async throws(AthleteError) -> FeedPage {
        FeedPage(posts: [.preview], nextCursor: nil)
    }
}

private struct ProtoStats: AthleteStatsRepository {
    func stats(of athleteId: String, sport: SportType?) async throws(AthleteError) -> AthleteStats { throw .network }
}

private struct ProtoProfiles: ProfileRepository {
    func editableProfile() async throws(AthleteError) -> EditableProfile { throw .network }
    func update(_ update: ProfileUpdate) async throws(AthleteError) -> ActivityAuthor { throw .network }
    func setApproveFollowers(_ approve: Bool) async throws(AthleteError) -> Bool { approve }
}

private struct ProtoGallery: AthleteGalleryRepository {
    func gallery(of athleteId: String, cursor: String?) async throws(AthleteError) -> GalleryPage {
        GalleryPage(items: [], nextCursor: nil)
    }
}

private struct ProtoKudos: AthleteKudosRepository {
    func setKudos(_ given: Bool, activityId: ActivityID) async throws(AthleteError) -> KudosState { throw .network }
}

private struct ProtoFollows: FollowRepository {
    func follow(_ athleteId: String) async throws(AthleteError) -> FollowChange { throw .network }
    func unfollow(_ athleteId: String) async throws(AthleteError) -> FollowChange { throw .network }
}

private struct ProtoProgress: ProgressRepository {
    func progress(sport: SportType) async throws(AthleteError) -> AthleteProgress {
        let calendar = ProgressCalendar.calendar
        let monday = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        var rng = ProtoRNG(seed: UInt64(ActivityFormatters.sportLabel(sport).count))
        let perWeek: Double = switch sport {
        case .ride: 140_000
        case .run: 32_000
        case .swim: 4_000
        default: 15_000
        }
        let weeks = (0..<12).reversed().map { back in
            let start = calendar.date(byAdding: .weekOfYear, value: -back, to: monday) ?? monday
            let meters = perWeek * (0.4 + rng.next())
            return WeekProgress(
                weekStart: CalendarDay(start, calendar: calendar),
                distance: Distance(meters: meters),
                elevationGain: meters / 90,
                movingTime: .seconds(Int(meters / 6)),
                activityCount: Int(rng.next() * 4) + 1
            )
        }
        let today = ProgressCalendar.today()
        let days = Set((1...max(1, today.day)).filter { $0 % 3 == 0 }.map { CalendarDay(year: today.year, month: today.month, day: $0) })
        return AthleteProgress(sport: sport, weeks: weeks, streakWeeks: 6, activeDays: days)
    }
}
#endif
