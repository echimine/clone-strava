import Foundation
import Observation

/// State of the Home feed (ADR-029): first load and pull-to-refresh, infinite scroll,
/// optimistic kudos, and reload when one of the user's activities finishes processing.
/// Processed cards open the Activity detail, and follow what it publishes on the Core change
/// stream (ADR-033 §1, §7).
@Observable
@MainActor
final class FeedStore {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(message: String)
    }

    private(set) var posts: [ActivityPost] = []
    /// Local Activities not yet processed (ADR-031 §14), newest first.
    private var allLocalCards: [LocalActivityCard] = []
    private(set) var phase: Phase = .idle
    private(set) var isLoadingMore = false
    /// Short-lived error shown over the list (e.g. a kudos that could not be sent).
    var notice: String?

    /// Loads the next page when the user reaches this many cards from the end.
    @ObservationIgnored let prefetchDistance = 3
    @ObservationIgnored private let loadFeed: LoadFeed
    @ObservationIgnored private let toggleKudos: ToggleKudos
    @ObservationIgnored private let events: any FeedEventSource
    @ObservationIgnored private var nextCursor: String?
    @ObservationIgnored private var refreshGeneration = 0
    @ObservationIgnored private var kudosInFlight: Set<ActivityID> = []
    /// Run on pull-to-refresh beside the reload: the app shell sends the queued operations
    /// (ADR-031 §14).
    @ObservationIgnored private let onPullToRefresh: @MainActor () async -> Void
    @ObservationIgnored private let localActivities: (any LocalActivityFeedSource)?
    /// Bumped to bring the list back to its top (after Save, ADR-031 §11).
    private(set) var scrollToTopRequest = 0
    /// Navigation of the Home tab: the Activity details opened from the feed.
    var path: [ActivityDetailRequest] = []
    /// Applies the change stream for the store's lifetime, even while a detail covers the feed.
    @ObservationIgnored private var changeObservation: Task<Void, Never>?
    /// The cards a `.deleted` change removed since the last refresh, with their place, for a
    /// deletion the server turns down (`.restored`).
    @ObservationIgnored private var removedPosts: [ActivityID: (index: Int, post: ActivityPost)] = [:]

    init(
        loadFeed: LoadFeed,
        toggleKudos: ToggleKudos,
        events: any FeedEventSource,
        localActivities: (any LocalActivityFeedSource)? = nil,
        activityChanges: ActivityChanges? = nil,
        onPullToRefresh: @escaping @MainActor () async -> Void = {}
    ) {
        self.loadFeed = loadFeed
        self.toggleKudos = toggleKudos
        self.events = events
        self.localActivities = localActivities
        self.onPullToRefresh = onPullToRefresh
        // Subscribed here, not in a view task: a pushed detail would cancel the feed's tasks.
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

    /// Always on top (ADR-031 §14); a local card whose UUID the server already returned is dropped.
    var localCards: [LocalActivityCard] {
        let served = Set(posts.map(\.id))
        return allLocalCards.filter { !served.contains($0.id) }
    }

    var isEmpty: Bool { phase == .loaded && posts.isEmpty && localCards.isEmpty }

    /// Sign-out: forgets the previous account's feed.
    func reset() {
        refreshGeneration += 1
        posts = []
        removedPosts = [:]
        nextCursor = nil
        phase = .idle
        notice = nil
        path = []
    }

    /// Tap on a card outside its buttons, or its comment button: only a processed card, one the
    /// server returned, opens the detail; local cards are not tappable (ADR-033 §1).
    func open(_ id: ActivityID, showingComments: Bool = false) {
        guard posts.contains(where: { $0.id == id }) else { return }
        path.append(ActivityDetailRequest(id: id, showsComments: showingComments))
    }

    /// Long press (ADR-033 §1): the "Modifier" menu is only on my processed cards, the ones the
    /// server returned; local cards keep their own menu.
    func canManage(_ id: ActivityID) -> Bool {
        posts.first { $0.id == id }?.viewerIsAuthor == true
    }

    /// A change made away from the feed (ADR-033 §7). Activities the feed does not show are
    /// ignored: the change stream never adds a card, it only puts back one it removed.
    func apply(_ change: ActivityChange) {
        switch change {
        case .updated(let post):
            guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
            posts[index] = post
        case .deleted(let id):
            guard let index = posts.firstIndex(where: { $0.id == id }) else { return }
            removedPosts[id] = (index, posts.remove(at: index))
        case .restored(let id):
            guard let removed = removedPosts.removeValue(forKey: id), !posts.contains(where: { $0.id == id }) else { return }
            posts.insert(removed.post, at: min(removed.index, posts.count))
        case .engagement(let id, let engagement):
            update(id) { $0 = engagement }
        }
    }

    /// First appearance: loads once.
    func loadIfNeeded() async {
        guard phase == .idle else { return }
        await refresh()
    }

    /// Pull-to-refresh: the first page, and the queued operations sent meanwhile.
    func pullToRefresh() async {
        async let sending: Void = onPullToRefresh()
        await refresh()
        await sending
    }

    /// Back to the top of the list, then the first page again.
    func showTop() async {
        scrollToTopRequest += 1
        await refresh()
    }

    /// Replaces the list with the first page. A newer refresh wins over an older one. `true`
    /// once the first page is shown.
    @discardableResult
    func refresh() async -> Bool {
        refreshGeneration += 1
        let generation = refreshGeneration
        if posts.isEmpty {
            phase = .loading
        }
        do {
            let page = try await loadFeed()
            guard generation == refreshGeneration else { return false }
            posts = page.posts
            removedPosts = [:]
            nextCursor = page.nextCursor
            phase = .loaded
            return true
        } catch {
            guard generation == refreshGeneration else { return false }
            if posts.isEmpty {
                phase = .failed(message: FeedMessages.message(for: error))
            } else {
                notice = FeedMessages.message(for: error)
            }
            return false
        }
    }

    /// Called when a card appears: fetches the next page near the end of the list.
    func loadMoreIfNeeded(currentPost: ActivityPost) async {
        guard
            let cursor = nextCursor,
            !isLoadingMore,
            let index = posts.firstIndex(where: { $0.id == currentPost.id }),
            index >= posts.count - prefetchDistance
        else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let generation = refreshGeneration
        do {
            let page = try await loadFeed(cursor: cursor)
            guard generation == refreshGeneration else { return }
            let known = Set(posts.map(\.id))
            posts.append(contentsOf: page.posts.filter { !known.contains($0.id) })
            nextCursor = page.nextCursor
        } catch {
            notice = FeedMessages.message(for: error)
        }
    }

    /// Optimistic kudos: the card changes at once, then takes the server's count, or rolls
    /// back on failure. Taps while a request is in flight for the same card are ignored.
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
            let state = try await toggleKudos(optimistic.viewerHasKudoed, activityId: id)
            update(id) {
                $0.kudosCount = state.kudosCount
                $0.viewerHasKudoed = state.viewerHasKudoed
            }
        } catch {
            update(id) { $0 = previous }
            notice = FeedMessages.kudosFailed(error)
        }
    }

    /// Runs for the lifetime of the view (`.task`): reloads when an activity finishes processing.
    func observeActivityChanges() async {
        for await _ in await events.activityChanges() {
            await refresh()
        }
    }

    /// Runs for the lifetime of the view (`.task`): follows the local Activities, and reports a
    /// Delete the server turned down.
    func observeLocalActivities() async {
        guard let localActivities else { return }
        let refusals = localActivities.deletionRefusals()
        let reporting = Task { [weak self] in
            for await _ in refusals {
                self?.notice = FeedMessages.localDeletionRefused
            }
        }
        defer { reporting.cancel() }
        for await cards in localActivities.cards() {
            allLocalCards = cards
        }
    }

    /// Delete, once confirmed (ADR-031 §14): the card goes at once.
    func deleteLocalActivity(_ id: ActivityID) async {
        await performLocal { try await $0.delete(id) }
    }

    /// Retry after an API refusal: the Activity resumes at the refused step.
    func retryLocalActivity(_ id: ActivityID) async {
        await performLocal { try await $0.retry(id) }
    }

    private func performLocal(_ action: @MainActor (any LocalActivityFeedSource) async throws -> Void) async {
        guard let localActivities else { return }
        do {
            try await action(localActivities)
        } catch {
            notice = FeedMessages.localActionRefused
        }
    }

    private func update(_ id: ActivityID, _ change: (inout ActivityEngagement) -> Void) {
        guard let index = posts.firstIndex(where: { $0.id == id }) else { return }
        change(&posts[index].engagement)
    }
}
