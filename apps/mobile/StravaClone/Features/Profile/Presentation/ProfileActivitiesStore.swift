import Foundation
import Observation

/// The profile's Activités tab (ADR-036 §3): my Activities as feed cards, infinite scroll, and
/// what a detail changes or deletes (ADR-033 §7), through the shared `AthleteActivitiesPager`.
/// My own cards have no kudos button.
@Observable
@MainActor
final class ProfileActivitiesStore {
    typealias Phase = AthleteActivitiesPager.Phase

    @ObservationIgnored private let pager: AthleteActivitiesPager
    @ObservationIgnored private let analytics: any AnalyticsClient
    /// The full-screen viewer, opened by a tap on a card's Media (ADR-037 §10).
    var mediaViewer: MediaViewerRequest?

    init(
        loadActivities: LoadProfileActivities,
        activityChanges: ActivityChanges? = nil,
        analytics: any AnalyticsClient = NoAnalyticsClient()
    ) {
        self.analytics = analytics
        pager = AthleteActivitiesPager(
            load: { athleteId, cursor async throws(AthleteError) in
                try await loadActivities(athleteId: athleteId, cursor: cursor)
            },
            message: ProfileMessages.message(for:),
            activityChanges: activityChanges
        )
    }

    var posts: [ActivityPost] { pager.posts }
    var phase: Phase { pager.phase }
    var isLoadingMore: Bool { pager.isLoadingMore }
    var isEmpty: Bool { pager.isEmpty }
    var prefetchDistance: Int { pager.prefetchDistance }

    /// Short-lived error shown over the list (a page that could not be loaded).
    var notice: String? {
        get { pager.notice }
        set { pager.notice = newValue }
    }

    /// The first page of this athlete's Activities. A newer refresh wins over an older one.
    func refresh(athleteId: String) async {
        await pager.refresh(athleteId: athleteId)
    }

    /// Called when a card appears: fetches the next page near the end of the list.
    func loadMoreIfNeeded(currentPost: ActivityPost) async {
        await pager.loadMoreIfNeeded(currentPost: currentPost)
    }

    /// A tap on a Media of a card's carousel: the viewer on the Activity's Media (ADR-037 §10).
    func openMedia(_ media: ActivityMedia, of id: ActivityID) {
        guard let post = posts.first(where: { $0.id == id }),
              let request = MediaViewerRequest.activity(post, at: media) else { return }
        analytics.capture(request.openedEvent(source: .profileActivities, isOwn: post.viewerIsAuthor))
        mediaViewer = request
    }

    /// A change made in a detail (ADR-033 §7); Activities the list does not show are ignored.
    func apply(_ change: ActivityChange) {
        pager.apply(change)
    }

    /// Sign-out: forgets the previous account's Activities.
    func reset() {
        pager.reset()
    }
}
