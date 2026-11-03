import Foundation
import Observation

/// An athlete's followers and following lists (ADR-036 §1, §10), opened from their counters:
/// "Abonnés · N" and "Abonnements · N", each paged, with a follow button on every row. On the
/// viewer's own followers: the "Demandes d'abonnement" row and removing a follower. One per
/// pushed lists screen.
@Observable
@MainActor
final class FollowListStore {
    typealias Kind = AthleteFollowsRequest.Kind

    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(message: String)
    }

    /// One list's rows and paging.
    struct Listing {
        var items: [AthleteListItem] = []
        var phase = Phase.idle
        var nextCursor: String?
        var isLoadingMore = false
    }

    let athleteId: String
    let athleteName: String
    let isOwn: Bool
    var selected: Kind
    private(set) var followerCount: Int
    private(set) var followingCount: Int
    private(set) var pendingRequestCount: Int
    private(set) var listings: [Kind: Listing] = [:]
    /// What went wrong with a page or a removal.
    var toast: String?

    let follows: FollowStore
    /// "Demandes d'abonnement", on the viewer's own lists.
    let requests: FollowRequestsStore

    @ObservationIgnored let prefetchDistance = 3
    @ObservationIgnored private let loadList: LoadFollowList
    @ObservationIgnored private let removeFollowerUseCase: RemoveFollower
    @ObservationIgnored private let ownCountsChanged: @MainActor (FollowCountsChange) -> Void
    @ObservationIgnored private var generations: [Kind: Int] = [:]
    @ObservationIgnored private var removing: Set<String> = []

    /// `ownCountsChanged` hears what this screen changes to the viewer's followers and requests,
    /// for the Profile tab's header.
    init(
        request: AthleteFollowsRequest,
        loadList: LoadFollowList,
        removeFollower: RemoveFollower,
        follows: FollowStore,
        requests: FollowRequestsStore,
        ownCountsChanged: @escaping @MainActor (FollowCountsChange) -> Void = { _ in }
    ) {
        athleteId = request.athleteId
        athleteName = request.athleteName
        isOwn = request.isOwn
        selected = request.list
        followerCount = request.followerCount
        followingCount = request.followingCount
        pendingRequestCount = request.pendingRequestCount
        self.loadList = loadList
        removeFollowerUseCase = removeFollower
        self.follows = follows
        self.requests = requests
        self.ownCountsChanged = ownCountsChanged
        requests.onAccepted = { [weak self] in self?.requestAccepted($0) }
        requests.onGone = { [weak self] in self?.change(FollowCountsChange(pendingRequests: -1)) }
        if request.isOwn {
            // My own following counter moves with my follow buttons.
            follows.observeChanges { [weak self] previous, change in
                self?.followingCount += FollowCountsChange.following(from: previous, to: change.status).following
            }
        }
    }

    func items(of list: Kind) -> [AthleteListItem] { listings[list]?.items ?? [] }
    func phase(of list: Kind) -> Phase { listings[list]?.phase ?? .idle }
    func isLoadingMore(_ list: Kind) -> Bool { listings[list]?.isLoadingMore ?? false }

    /// "Demandes d'abonnement", above my followers while someone asks.
    var showsRequestsRow: Bool { isOwn && selected == .followers && pendingRequestCount > 0 }
    /// Swipe to remove: my own followers only.
    var canRemoveFollowers: Bool { isOwn }

    /// First appearance: the tapped list, once.
    func load() async {
        await show(selected)
    }

    /// A segment chosen: its list loads the first time it shows.
    func show(_ list: Kind) async {
        selected = list
        guard phase(of: list) == .idle else { return }
        await refresh(list)
    }

    /// Pull-to-refresh and "Réessayer": the shown list's first page again.
    func refresh() async {
        await refresh(selected)
    }

    func loadMoreIfNeeded(current item: AthleteListItem) async {
        let list = selected
        guard
            let listing = listings[list],
            let cursor = listing.nextCursor,
            !listing.isLoadingMore,
            let index = listing.items.firstIndex(where: { $0.id == item.id }),
            index >= listing.items.count - prefetchDistance
        else { return }
        listings[list]?.isLoadingMore = true
        defer { listings[list]?.isLoadingMore = false }
        let current = generations[list]
        do {
            let page = try await loadList(list, of: athleteId, cursor: cursor)
            guard current == generations[list] else { return }
            track(page.items)
            let known = Set(items(of: list).map(\.id))
            listings[list]?.items.append(contentsOf: page.items.filter { !known.contains($0.id) })
            listings[list]?.nextCursor = page.nextCursor
        } catch {
            toast = AthletesMessages.message(for: error)
        }
    }

    /// Swipe, then "Retirer": the row leaves at once, and comes back with a toast if the server
    /// turns it down.
    func removeFollower(_ followerId: String) async {
        guard
            canRemoveFollowers,
            !removing.contains(followerId),
            let index = items(of: .followers).firstIndex(where: { $0.id == followerId }),
            let item = listings[.followers]?.items.remove(at: index)
        else { return }
        removing.insert(followerId)
        defer { removing.remove(followerId) }
        followerCount = max(0, followerCount - 1)
        do {
            try await removeFollowerUseCase(followerId)
            ownCountsChanged(FollowCountsChange(followers: -1))
        } catch {
            let position = min(index, items(of: .followers).count)
            listings[.followers]?.items.insert(item, at: position)
            followerCount += 1
            toast = AthletesMessages.message(for: error)
        }
    }

    private func refresh(_ list: Kind) async {
        let current = (generations[list] ?? 0) + 1
        generations[list] = current
        if items(of: list).isEmpty {
            listings[list, default: Listing()].phase = .loading
        }
        do {
            let page = try await loadList(list, of: athleteId)
            guard current == generations[list] else { return }
            track(page.items)
            listings[list] = Listing(items: page.items, phase: .loaded, nextCursor: page.nextCursor)
        } catch {
            guard current == generations[list] else { return }
            if items(of: list).isEmpty {
                listings[list, default: Listing()].phase = .failed(message: AthletesMessages.message(for: error))
            } else {
                toast = AthletesMessages.message(for: error)
            }
        }
    }

    private func track(_ items: [AthleteListItem]) {
        for item in items {
            follows.track(item.id, status: item.viewerFollowStatus)
        }
    }

    /// An accepted request: a new follower, at the top of my followers once they are shown.
    private func requestAccepted(_ request: FollowRequest) {
        let item = AthleteListItem(athlete: request.athlete, viewerFollowStatus: request.viewerFollowStatus)
        follows.track(item.id, status: item.viewerFollowStatus)
        if phase(of: .followers) == .loaded, !items(of: .followers).contains(where: { $0.id == item.id }) {
            listings[.followers]?.items.insert(item, at: 0)
        }
        change(FollowCountsChange(followers: 1, pendingRequests: -1))
    }

    private func change(_ change: FollowCountsChange) {
        followerCount = max(0, followerCount + change.followers)
        pendingRequestCount = max(0, pendingRequestCount + change.pendingRequests)
        ownCountsChanged(change)
    }
}
