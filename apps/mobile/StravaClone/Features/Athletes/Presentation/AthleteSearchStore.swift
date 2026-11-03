import Foundation
import Observation

/// The athlete search (ADR-036 §2), behind the profile's magnifier: searches once the typing
/// pauses and the query has at least 2 letters, each new query cancelling the previous one,
/// then shows the results with their follow buttons. One per pushed search screen.
@Observable
@MainActor
final class AthleteSearchStore {
    enum Phase: Equatable {
        /// Fewer than 2 letters: nothing searched.
        case idle
        case searching
        case loaded
        case failed(message: String)
    }

    static let minimumLength = 2
    static let debounce = Duration.milliseconds(300)

    private(set) var query = ""
    private(set) var results: [AthleteListItem] = []
    private(set) var phase = Phase.idle

    let follows: FollowStore

    @ObservationIgnored private let searchAthletes: SearchAthletes
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var pending: Task<Void, Never>?

    init(
        searchAthletes: SearchAthletes,
        follows: FollowStore,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.searchAthletes = searchAthletes
        self.follows = follows
        self.sleep = sleep
    }

    /// "Aucun athlète trouvé".
    var isEmpty: Bool { phase == .loaded && results.isEmpty }

    /// Each change of the field: cancels the search in flight, then searches the trimmed query
    /// after a pause. Nil when the query is too short to be searched.
    @discardableResult
    func updateQuery(_ text: String) -> Task<Void, Never>? {
        query = text
        pending?.cancel()
        pending = nil
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.minimumLength else {
            results = []
            phase = .idle
            return nil
        }
        phase = .searching
        let task = Task { [weak self, sleep] in
            do {
                try await sleep(Self.debounce)
            } catch {
                return
            }
            await self?.search(trimmed)
        }
        pending = task
        return task
    }

    private func search(_ query: String) async {
        guard !Task.isCancelled else { return }
        do {
            let found = try await searchAthletes(query)
            guard !Task.isCancelled else { return }
            for item in found {
                follows.track(item.id, status: item.viewerFollowStatus)
            }
            results = found
            phase = .loaded
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(message: AthletesMessages.message(for: error))
        }
    }
}
