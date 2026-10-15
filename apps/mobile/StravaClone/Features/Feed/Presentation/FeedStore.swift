import Foundation
import Observation

/// State of the Home feed (ADR-029): first load and pull-to-refresh, infinite scroll,
/// optimistic kudos, and reload when one of the user's activities finishes processing.
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
    /// Bumped to bring the list back to its top (after Save, ADR-031 §11).
    private(set) var scrollToTopRequest = 0

    init(
        loadFeed: LoadFeed,
        toggleKudos: ToggleKudos,
        events: any FeedEventSource,
        onPullToRefresh: @escaping @MainActor () async -> Void = {}
    ) {
        self.loadFeed = loadFeed
        self.toggleKudos = toggleKudos
        self.events = events
        self.onPullToRefresh = onPullToRefresh
    }

    var isEmpty: Bool { phase == .loaded && posts.isEmpty }

    /// Sign-out: forgets the previous account's feed.
    func reset() {
        refreshGeneration += 1
        posts = []
        nextCursor = nil
        phase = .idle
        notice = nil
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

    private func update(_ id: ActivityID, _ change: (inout ActivityEngagement) -> Void) {
        guard let index = posts.firstIndex(where: { $0.id == id }) else { return }
        change(&posts[index].engagement)
    }
}
