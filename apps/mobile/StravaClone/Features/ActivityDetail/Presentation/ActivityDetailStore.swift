import Foundation
import Observation

/// State of an Activity's detail (ADR-033 §3), read from the API on each opening (no cache,
/// ADR-033 §7). A failed reload keeps what is shown; a `404` replaces it with the unavailable
/// state, and the screen is never closed by force.
@Observable
@MainActor
final class ActivityDetailStore {
    enum Phase: Equatable {
        case loading
        case loaded(ActivityDetail)
        case failed(message: String)
        /// Deleted or no longer visible: "Cette activité n'est plus disponible".
        case unavailable
    }

    /// How many givers the kudos row shows (ADR-034 §1).
    static let recentKudosLimit = 5

    let id: ActivityID
    private(set) var phase: Phase = .loading
    /// "⋯" > "Modifier" (ADR-033 §7): what it shows replaces the detail at once.
    let editor: ActivityEditor
    /// The most recent kudos givers, for the kudos row (at most `recentKudosLimit`).
    private(set) var recentKudos: [KudosGiver] = []
    /// Short-lived error shown over the detail (a kudos that could not be sent).
    var kudosNotice: String?

    @ObservationIgnored private let loadDetail: LoadActivityDetail
    @ObservationIgnored private let loadKudos: LoadKudosList
    @ObservationIgnored private let setKudos: SetActivityKudos
    @ObservationIgnored private let changes: ActivityChanges
    @ObservationIgnored private let events: (any ActivityEventSource)?
    @ObservationIgnored private let deleter: ActivityDeleter
    @ObservationIgnored private var kudosInFlight = false

    /// - Parameters:
    ///   - changes: where the detail publishes what changed, for the feed (ADR-033 §7).
    ///   - updateActivity: "Enregistrer" of the edit sheet; by default over `loadDetail`'s
    ///     repository.
    ///   - events: realtime events; this Activity's `activity.updated` reloads it,
    ///     `activity.deleted` makes it unavailable (§8).
    ///   - deleter: "⋯" > "Supprimer"; the feed's, so that a failure shows over the feed the
    ///     page has gone back to (§7).
    init(
        id: ActivityID,
        loadDetail: LoadActivityDetail,
        loadKudos: LoadKudosList,
        setKudos: SetActivityKudos,
        changes: ActivityChanges,
        updateActivity: UpdateActivity? = nil,
        events: (any ActivityEventSource)? = nil,
        deleter: ActivityDeleter? = nil
    ) {
        self.id = id
        self.deleter = deleter ?? ActivityDeleter(
            deleteActivity: DeleteActivity(repository: loadDetail.repository),
            changes: changes
        )
        self.loadDetail = loadDetail
        self.loadKudos = loadKudos
        self.setKudos = setKudos
        self.changes = changes
        self.events = events
        editor = ActivityEditor(
            loadDetail: loadDetail,
            updateActivity: updateActivity ?? UpdateActivity(repository: loadDetail.repository),
            changes: changes
        )
        editor.onChange = { [weak self] detail in self?.phase = .loaded(detail) }
        editor.onUnavailable = { [weak self] in self?.phase = .unavailable }
    }

    /// Runs while the detail is shown (`.task`): this Activity's realtime events. The echo of
    /// the athlete's own edit reloads the same values; a deletion makes it unavailable (§3, §8).
    func observeEvents() async {
        guard let events else { return }
        for await event in await events.activityEvents() {
            switch event {
            case .updated(id):
                await load()
            case .deleted(id):
                phase = .unavailable
                changes.publish(.deleted(id))
            default:
                continue
            }
        }
    }

    var detail: ActivityDetail? {
        guard case .loaded(let detail) = phase else { return nil }
        return detail
    }

    /// First appearance, and any reload (e.g. a realtime `activity.updated` or `kudos.changed`).
    /// What it learns reaches the feed: the fresh card, or that the Activity is gone.
    func load() async {
        async let recent = recentKudosPage()
        do {
            let detail = try await loadDetail(id)
            phase = .loaded(detail)
            changes.publish(.updated(detail.post))
        } catch .notFound {
            phase = .unavailable
            changes.publish(.deleted(id))
        } catch {
            if detail == nil {
                phase = .failed(message: ActivityDetailMessages.message(for: error))
            }
        }
        if let givers = await recent {
            recentKudos = givers
        }
    }

    /// A comment gained or lost on the thread (ADR-034 §6): the count reaches the feed card.
    func commentCountChanged(by delta: Int) {
        setEngagement { $0.commentCount = max(0, $0.commentCount + delta) }
    }

    /// "⋯" > "Supprimer", once confirmed: the page goes back to the feed, where the card is
    /// already gone (ADR-033 §7).
    func delete() async {
        await deleter.delete(id)
    }

    /// "Réessayer" after an error.
    func retry() async {
        phase = .loading
        await load()
    }

    // MARK: Kudos (ADR-034 §1)

    /// The viewer cannot give kudos to their own Activity: the button is hidden there.
    var showsKudosButton: Bool {
        detail.map { !$0.viewerIsAuthor } ?? false
    }

    /// Optimistic, like `FeedStore.toggleKudos`: the count changes at once, then takes the
    /// server's answer, or rolls back with a notice. Each step reaches the feed card. Taps while
    /// a request is in flight are ignored.
    func toggleKudos() async {
        guard !kudosInFlight, let current = detail, !current.viewerIsAuthor else { return }
        let previous = current.engagement
        let optimistic = previous.togglingKudos()
        setEngagement { $0 = optimistic }
        kudosInFlight = true
        defer { kudosInFlight = false }

        do {
            let state = try await setKudos(optimistic.viewerHasKudoed, activityId: id)
            setEngagement {
                $0.kudosCount = state.kudosCount
                $0.viewerHasKudoed = state.viewerHasKudoed
            }
            if let givers = await recentKudosPage() {
                recentKudos = givers
            }
        } catch {
            setEngagement { $0 = previous }
            kudosNotice = ActivityDetailMessages.kudosFailed(error)
        }
    }

    /// The sheet listing every giver, opened from the kudos row.
    func makeKudosListStore() -> KudosListStore {
        KudosListStore(activityId: id, loadKudos: loadKudos)
    }

    /// Nil when the row could not be loaded: what is shown stays.
    private func recentKudosPage() async -> [KudosGiver]? {
        let page = try? await loadKudos(id, limit: Self.recentKudosLimit)
        return page.map { Array($0.givers.prefix(Self.recentKudosLimit)) }
    }

    /// Changes the loaded detail's counts and tells the feed (ADR-033 §7).
    private func setEngagement(_ change: (inout ActivityEngagement) -> Void) {
        guard var detail else { return }
        change(&detail.engagement)
        phase = .loaded(detail)
        changes.publish(.engagement(id, detail.engagement))
    }
}
