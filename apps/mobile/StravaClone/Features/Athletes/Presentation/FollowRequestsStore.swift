import Foundation
import Observation

/// "Demandes d'abonnement" (ADR-036 §1): who asks to follow the viewer, with Accepter and
/// Refuser. A request leaves the list at once; it comes back with a toast if the server turns
/// the answer down, and stays gone if it no longer exists (cancelled meanwhile).
@Observable
@MainActor
final class FollowRequestsStore {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(message: String)
    }

    private(set) var items: [FollowRequest] = []
    private(set) var phase = Phase.idle
    private(set) var isLoadingMore = false
    var toast: String?

    /// A request accepted: its athlete is now a follower.
    @ObservationIgnored var onAccepted: @MainActor (FollowRequest) -> Void = { _ in }
    /// A request refused, or no longer there.
    @ObservationIgnored var onGone: @MainActor () -> Void = {}

    @ObservationIgnored let prefetchDistance = 3
    @ObservationIgnored private let loadRequests: LoadFollowRequests
    @ObservationIgnored private let acceptRequest: AcceptFollowRequest
    @ObservationIgnored private let refuseRequest: RefuseFollowRequest
    @ObservationIgnored private var nextCursor: String?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var inFlight: Set<String> = []

    init(loadRequests: LoadFollowRequests, acceptRequest: AcceptFollowRequest, refuseRequest: RefuseFollowRequest) {
        self.loadRequests = loadRequests
        self.acceptRequest = acceptRequest
        self.refuseRequest = refuseRequest
    }

    var isEmpty: Bool { phase == .loaded && items.isEmpty }

    /// First appearance: loads once.
    func load() async {
        guard phase == .idle else { return }
        await refresh()
    }

    func refresh() async {
        generation += 1
        let current = generation
        if items.isEmpty {
            phase = .loading
        }
        do {
            let page = try await loadRequests()
            guard current == generation else { return }
            items = page.items
            nextCursor = page.nextCursor
            phase = .loaded
        } catch {
            guard current == generation else { return }
            if items.isEmpty {
                phase = .failed(message: AthletesMessages.message(for: error))
            } else {
                toast = AthletesMessages.message(for: error)
            }
        }
    }

    func loadMoreIfNeeded(current request: FollowRequest) async {
        guard
            let cursor = nextCursor,
            !isLoadingMore,
            let index = items.firstIndex(where: { $0.id == request.id }),
            index >= items.count - prefetchDistance
        else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let current = generation
        do {
            let page = try await loadRequests(cursor: cursor)
            guard current == generation else { return }
            let known = Set(items.map(\.id))
            items.append(contentsOf: page.items.filter { !known.contains($0.id) })
            nextCursor = page.nextCursor
        } catch {
            toast = AthletesMessages.message(for: error)
        }
    }

    /// "Accepter".
    func accept(_ athleteId: String) async {
        await answer(athleteId, failure: AthletesMessages.acceptFailed) { [acceptRequest, onAccepted] request async throws(AthleteError) in
            try await acceptRequest(from: athleteId)
            onAccepted(request)
        }
    }

    /// "Refuser".
    func refuse(_ athleteId: String) async {
        await answer(athleteId, failure: AthletesMessages.refuseFailed) { [refuseRequest, onGone] _ async throws(AthleteError) in
            try await refuseRequest(from: athleteId)
            onGone()
        }
    }

    private func answer(
        _ athleteId: String,
        failure: String,
        _ send: (FollowRequest) async throws(AthleteError) -> Void
    ) async {
        guard !inFlight.contains(athleteId), let index = items.firstIndex(where: { $0.id == athleteId }) else { return }
        let request = items[index]
        inFlight.insert(athleteId)
        defer { inFlight.remove(athleteId) }
        items.remove(at: index)
        do {
            try await send(request)
        } catch .notFound {
            onGone()
        } catch {
            items.insert(request, at: min(index, items.count))
            toast = error == .offline ? AthletesMessages.message(for: error) : failure
        }
    }
}
