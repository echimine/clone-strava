import Foundation
import Observation

/// Another athlete's Activités tab (ADR-036 §3): their Activities the viewer may see, as feed
/// cards, with infinite scroll and what a detail changes or deletes (the shared
/// `AthleteActivitiesPager`), plus optimistic kudos sent back to the feed (ADR-033 §7).
@Observable
@MainActor
final class AthleteActivitiesStore {
    typealias Phase = AthleteActivitiesPager.Phase

    @ObservationIgnored private let pager: AthleteActivitiesPager
    @ObservationIgnored private let setKudos: SetAthleteActivityKudos
    @ObservationIgnored private let activityChanges: ActivityChanges?
    @ObservationIgnored private var kudosInFlight: Set<ActivityID> = []

    init(loadActivities: LoadAthleteActivities, setKudos: SetAthleteActivityKudos, activityChanges: ActivityChanges? = nil) {
        pager = AthleteActivitiesPager(
            load: { athleteId, cursor async throws(AthleteError) in
                try await loadActivities(athleteId: athleteId, cursor: cursor)
            },
            message: AthletesMessages.message(for:),
            activityChanges: activityChanges
        )
        self.setKudos = setKudos
        self.activityChanges = activityChanges
    }

    var posts: [ActivityPost] { pager.posts }
    var phase: Phase { pager.phase }
    var isLoadingMore: Bool { pager.isLoadingMore }
    var isEmpty: Bool { pager.isEmpty }
    var prefetchDistance: Int { pager.prefetchDistance }

    /// Short-lived error shown over the list (a page or a kudos that failed).
    var notice: String? {
        get { pager.notice }
        set { pager.notice = newValue }
    }

    /// The first page. A newer refresh wins over an older one.
    func refresh(athleteId: String) async {
        await pager.refresh(athleteId: athleteId)
    }

    /// Called when a card appears: fetches the next page near the end of the list.
    func loadMoreIfNeeded(currentPost: ActivityPost) async {
        await pager.loadMoreIfNeeded(currentPost: currentPost)
    }

    /// Optimistic kudos, as on the feed (ADR-029): the card changes at once, then takes the
    /// server's count, which reaches the feed, or rolls back.
    func toggleKudos(on id: ActivityID) async {
        guard
            !kudosInFlight.contains(id),
            let index = pager.posts.firstIndex(where: { $0.id == id }),
            !pager.posts[index].viewerIsAuthor
        else { return }
        let previous = pager.posts[index].engagement
        let optimistic = previous.togglingKudos()
        pager.posts[index].engagement = optimistic
        kudosInFlight.insert(id)
        defer { kudosInFlight.remove(id) }
        do {
            let state = try await setKudos(optimistic.viewerHasKudoed, activityId: id)
            guard let index = pager.posts.firstIndex(where: { $0.id == id }) else { return }
            pager.posts[index].engagement.kudosCount = state.kudosCount
            pager.posts[index].engagement.viewerHasKudoed = state.viewerHasKudoed
            activityChanges?.publish(.engagement(id, pager.posts[index].engagement))
        } catch {
            if let index = pager.posts.firstIndex(where: { $0.id == id }) {
                pager.posts[index].engagement = previous
            }
            notice = AthletesMessages.kudosFailed(error)
        }
    }

    /// A change made in a detail (ADR-033 §7); Activities the list does not show are ignored.
    func apply(_ change: ActivityChange) {
        pager.apply(change)
    }
}
