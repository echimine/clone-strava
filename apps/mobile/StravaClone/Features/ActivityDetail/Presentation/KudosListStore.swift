import Foundation
import Observation

/// The sheet listing everyone who gave kudos to an Activity (ADR-034 §1): most recent first,
/// one page at a time as the list scrolls.
@Observable
@MainActor
final class KudosListStore {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(message: String)
    }

    private(set) var givers: [KudosGiver] = []
    private(set) var phase: Phase = .loading
    private(set) var isLoadingMore = false

    /// Loads the next page when the user reaches this many givers from the end.
    @ObservationIgnored let prefetchDistance = 3
    @ObservationIgnored private let activityId: ActivityID
    @ObservationIgnored private let loadKudos: LoadKudosList
    @ObservationIgnored private let pageSize: Int
    @ObservationIgnored private var nextCursor: String?

    init(activityId: ActivityID, loadKudos: LoadKudosList, pageSize: Int = 20) {
        self.activityId = activityId
        self.loadKudos = loadKudos
        self.pageSize = pageSize
    }

    /// The first page; also "Réessayer" after an error.
    func load() async {
        if givers.isEmpty {
            phase = .loading
        }
        do {
            let page = try await loadKudos(activityId, limit: pageSize)
            givers = page.givers
            nextCursor = page.nextCursor
            phase = .loaded
        } catch {
            if givers.isEmpty {
                phase = .failed(message: ActivityDetailMessages.message(for: error))
            }
        }
    }

    /// Called when a giver appears: fetches the next page near the end of the list. A failure
    /// keeps the list; reaching the end again retries.
    func loadMoreIfNeeded(current: KudosGiver) async {
        guard
            let cursor = nextCursor,
            !isLoadingMore,
            let index = givers.firstIndex(where: { $0.id == current.id }),
            index >= givers.count - prefetchDistance
        else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        guard let page = try? await loadKudos(activityId, cursor: cursor, limit: pageSize) else { return }
        let known = Set(givers.map(\.id))
        givers.append(contentsOf: page.givers.filter { !known.contains($0.id) })
        nextCursor = page.nextCursor
    }
}
