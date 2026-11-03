import Foundation
import Observation

/// Another athlete's Activités tab (ADR-036 §3): their Activities the viewer may see, as feed
/// cards, with infinite scroll, optimistic kudos sent back to the feed (ADR-033 §7), and what a
/// detail changes or deletes.
@Observable
@MainActor
final class AthleteActivitiesStore {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(message: String)
    }

    private(set) var posts: [ActivityPost] = []
    private(set) var phase: Phase = .idle
    private(set) var isLoadingMore = false
    /// Short-lived error shown over the list (a page or a kudos that failed).
    var notice: String?

    @ObservationIgnored let prefetchDistance = 3
    @ObservationIgnored private let loadActivities: LoadAthleteActivities
    @ObservationIgnored private let setKudos: SetAthleteActivityKudos
    @ObservationIgnored private let activityChanges: ActivityChanges?
    @ObservationIgnored private var athleteId: String?
    @ObservationIgnored private var nextCursor: String?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var kudosInFlight: Set<ActivityID> = []
    @ObservationIgnored private var changeObservation: Task<Void, Never>?

    init(loadActivities: LoadAthleteActivities, setKudos: SetAthleteActivityKudos, activityChanges: ActivityChanges? = nil) {
        self.loadActivities = loadActivities
        self.setKudos = setKudos
        self.activityChanges = activityChanges
        // Subscribed here, not in a view task: a pushed detail would cancel the page's tasks.
        if let changes = activityChanges?.subscribe() {
            changeObservation = Task { [weak self] in
                for await change in changes {
                    self?.apply(change)
                }
            }
        }
    }

    deinit {
        changeObservation?.cancel()
    }

    var isEmpty: Bool { phase == .loaded && posts.isEmpty }

    /// The first page. A newer refresh wins over an older one.
    func refresh(athleteId: String) async {
        generation += 1
        let current = generation
        self.athleteId = athleteId
        if posts.isEmpty {
            phase = .loading
        }
        do {
            let page = try await loadActivities(athleteId: athleteId)
            guard current == generation else { return }
            posts = page.posts
            nextCursor = page.nextCursor
            phase = .loaded
        } catch {
            guard current == generation else { return }
            if posts.isEmpty {
                phase = .failed(message: AthletesMessages.message(for: error))
            } else {
                notice = AthletesMessages.message(for: error)
            }
        }
    }

    /// Called when a card appears: fetches the next page near the end of the list.
    func loadMoreIfNeeded(currentPost: ActivityPost) async {
        guard
            let athleteId,
            let cursor = nextCursor,
            !isLoadingMore,
            let index = posts.firstIndex(where: { $0.id == currentPost.id }),
            index >= posts.count - prefetchDistance
        else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let current = generation
        do {
            let page = try await loadActivities(athleteId: athleteId, cursor: cursor)
            guard current == generation else { return }
            let known = Set(posts.map(\.id))
            posts.append(contentsOf: page.posts.filter { !known.contains($0.id) })
            nextCursor = page.nextCursor
        } catch {
            notice = AthletesMessages.message(for: error)
        }
    }

    /// Optimistic kudos, as on the feed (ADR-029): the card changes at once, then takes the
    /// server's count, which reaches the feed, or rolls back.
    func toggleKudos(on id: ActivityID) async {
        guard
            !kudosInFlight.contains(id),
            let index = posts.firstIndex(where: { $0.id == id }),
            !posts[index].viewerIsAuthor
        else { return }
        let previous = posts[index].engagement
        let optimistic = previous.togglingKudos()
        posts[index].engagement = optimistic
        kudosInFlight.insert(id)
        defer { kudosInFlight.remove(id) }
        do {
            let state = try await setKudos(optimistic.viewerHasKudoed, activityId: id)
            guard let index = posts.firstIndex(where: { $0.id == id }) else { return }
            posts[index].engagement.kudosCount = state.kudosCount
            posts[index].engagement.viewerHasKudoed = state.viewerHasKudoed
            activityChanges?.publish(.engagement(id, posts[index].engagement))
        } catch {
            if let index = posts.firstIndex(where: { $0.id == id }) {
                posts[index].engagement = previous
            }
            notice = AthletesMessages.kudosFailed(error)
        }
    }

    /// A change made in a detail (ADR-033 §7); Activities the list does not show are ignored.
    func apply(_ change: ActivityChange) {
        switch change {
        case .updated(var post):
            guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
            // The detail does not know these card-only values (ADR-036 §5).
            post.routeTrimmed = posts[index].routeTrimmed
            post.recentKudos = posts[index].recentKudos
            posts[index] = post
        case .deleted(let id):
            posts.removeAll { $0.id == id }
        case .restored:
            // Only the author deletes, and they do not see this list.
            break
        case .engagement(let id, let engagement):
            guard let index = posts.firstIndex(where: { $0.id == id }) else { return }
            posts[index].engagement = engagement
        }
    }
}
