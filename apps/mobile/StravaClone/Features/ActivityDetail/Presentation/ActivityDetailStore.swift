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

    @ObservationIgnored private let loadDetail: LoadActivityDetail
    @ObservationIgnored private let changes: ActivityChanges

    /// - Parameter changes: where the detail publishes what changed, for the feed (ADR-033 §7).
    init(id: ActivityID, loadDetail: LoadActivityDetail, changes: ActivityChanges) {
        self.id = id
        self.loadDetail = loadDetail
        self.changes = changes
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

    /// A comment gained or lost on the thread (ADR-034 §6): the count reaches the feed card.
    func commentCountChanged(by delta: Int) {
        guard case .loaded(var detail) = phase else { return }
        detail.engagement.commentCount = max(0, detail.engagement.commentCount + delta)
        phase = .loaded(detail)
        changes.publish(.engagement(id, detail.engagement))
    }

    /// "Réessayer" after an error.
    func retry() async {
        phase = .loading
        await load()
    }
}
