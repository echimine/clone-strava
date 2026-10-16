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

    let id: ActivityID
    private(set) var phase: Phase = .loading
    /// "⋯" > "Modifier" (ADR-033 §7): what it shows replaces the detail at once.
    let editor: ActivityEditor

    @ObservationIgnored private let loadDetail: LoadActivityDetail
    @ObservationIgnored private let changes: ActivityChanges
    @ObservationIgnored private let events: (any ActivityEventSource)?

    /// - Parameters:
    ///   - changes: where the detail publishes what changed, for the feed (ADR-033 §7).
    ///   - events: realtime events; this Activity's `activity.updated` reloads it (§8).
    init(
        id: ActivityID,
        loadDetail: LoadActivityDetail,
        updateActivity: UpdateActivity,
        changes: ActivityChanges,
        events: (any ActivityEventSource)? = nil
    ) {
        self.id = id
        self.loadDetail = loadDetail
        self.changes = changes
        self.events = events
        editor = ActivityEditor(loadDetail: loadDetail, updateActivity: updateActivity, changes: changes)
        editor.onChange = { [weak self] detail in self?.phase = .loaded(detail) }
    }

    /// Runs while the detail is shown (`.task`): this Activity's realtime events. The echo of
    /// the athlete's own edit reloads the same values.
    func observeEvents() async {
        guard let events else { return }
        for await event in await events.activityEvents() {
            if case .updated(id) = event {
                await load()
            }
        }
    }

    var detail: ActivityDetail? {
        guard case .loaded(let detail) = phase else { return nil }
        return detail
    }

    /// First appearance, and any reload (e.g. a realtime `activity.updated`). What it learns
    /// reaches the feed: the fresh card, or that the Activity is gone.
    func load() async {
        do {
            let detail = try await loadDetail(id)
            phase = .loaded(detail)
            changes.publish(.updated(detail.post))
        } catch .notFound {
            phase = .unavailable
            changes.publish(.deleted(id))
        } catch {
            guard detail == nil else { return }
            phase = .failed(message: ActivityDetailMessages.message(for: error))
        }
    }

    /// "Réessayer" after an error.
    func retry() async {
        phase = .loading
        await load()
    }
}
