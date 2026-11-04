import Foundation
import Observation

/// An athlete's Activities as feed cards (ADR-036 §3), shared by my Profile tab and another
/// athlete's profile: the first page, infinite scroll, and what a detail changes, deletes or
/// restores (ADR-033 §7). The stores of both features add their own actions on top.
@Observable
@MainActor
final class AthleteActivitiesPager {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(message: String)
    }

    typealias Load = @Sendable (_ athleteId: String, _ cursor: String?) async throws(AthleteError) -> FeedPage

    /// Settable for the stores' optimistic changes (kudos).
    var posts: [ActivityPost] = []
    private(set) var phase: Phase = .idle
    private(set) var isLoadingMore = false
    /// Short-lived error shown over the list (a page that could not be loaded).
    var notice: String?

    @ObservationIgnored let prefetchDistance = 3
    @ObservationIgnored private let load: Load
    @ObservationIgnored private let message: @MainActor (AthleteError) -> String
    @ObservationIgnored private var athleteId: String?
    @ObservationIgnored private var nextCursor: String?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var changeObservation: Task<Void, Never>?
    /// The cards a `.deleted` change removed since the last refresh, with their place.
    @ObservationIgnored private var removedPosts: [ActivityID: (index: Int, post: ActivityPost)] = [:]

    /// `message`: the feature's French text for a failed page.
    init(load: @escaping Load, message: @escaping @MainActor (AthleteError) -> String, activityChanges: ActivityChanges? = nil) {
        self.load = load
        self.message = message
        // Subscribed here, not in a view task: a pushed detail would cancel the tab's tasks.
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

    /// The first page of this athlete's Activities. A newer refresh wins over an older one.
    func refresh(athleteId: String) async {
        generation += 1
        let current = generation
        self.athleteId = athleteId
        if posts.isEmpty {
            phase = .loading
        }
        do {
            let page = try await load(athleteId, nil)
            guard current == generation else { return }
            posts = page.posts
            removedPosts = [:]
            nextCursor = page.nextCursor
            phase = .loaded
        } catch {
            guard current == generation else { return }
            if posts.isEmpty {
                phase = .failed(message: message(error))
            } else {
                notice = message(error)
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
            let page = try await load(athleteId, cursor)
            guard current == generation else { return }
            let known = Set(posts.map(\.id))
            posts.append(contentsOf: page.posts.filter { !known.contains($0.id) })
            nextCursor = page.nextCursor
        } catch {
            notice = message(error)
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
            guard let index = posts.firstIndex(where: { $0.id == id }) else { return }
            removedPosts[id] = (index, posts.remove(at: index))
        case .restored(let id):
            // A deletion the server turned down: the card comes back in its place.
            guard let removed = removedPosts.removeValue(forKey: id), !posts.contains(where: { $0.id == id }) else { return }
            posts.insert(removed.post, at: min(removed.index, posts.count))
        case .authorHidden(let athleteId):
            posts.removeAll { $0.author.id == athleteId }
        case .engagement(let id, let engagement):
            guard let index = posts.firstIndex(where: { $0.id == id }) else { return }
            posts[index].engagement = engagement
        }
    }

    /// Sign-out: forgets the previous account's Activities.
    func reset() {
        generation += 1
        posts = []
        removedPosts = [:]
        athleteId = nil
        nextCursor = nil
        phase = .idle
        notice = nil
    }
}
