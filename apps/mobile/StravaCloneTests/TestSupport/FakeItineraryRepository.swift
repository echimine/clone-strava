import Foundation
@testable import StravaClone

/// Hand-written `ItineraryRepository` (ADR-025 §3): scripted answers, recorded calls.
/// `hold()` suspends `page` calls until `release()`, to observe a resync in flight.
final class FakeItineraryRepository: ItineraryRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var _createResults: [Result<CreatedItinerary, ItineraryError>] = []
    private var _pages: [String?: Result<ItineraryPage, ItineraryError>] = [:]
    private var _creations: [ItineraryCreation] = []
    private var _pageCalls: [String?] = []
    private var _details: [ItineraryID: Result<ItineraryDetail, ItineraryError>] = [:]
    private var _detailCalls: [ItineraryID] = []
    private var _renameCalls: [(ItineraryID, String)] = []
    private var _deleteCalls: [ItineraryID] = []
    private var _changeResult: Result<Void, ItineraryError> = .failure(.offline)
    private var _saved: [ItineraryID: Result<SavedItinerary, ItineraryError>] = [:]
    private var _savedCalls: [ItineraryID] = []
    private var _updateResults: [Result<ItineraryDetail, ItineraryError>] = []
    private var _updates: [ItineraryCreation] = []
    private var gate: AsyncStream<Void>?
    private var gateContinuation: AsyncStream<Void>.Continuation?

    /// Answers of the next `create` calls, in order; the last one repeats.
    var createResults: [Result<CreatedItinerary, ItineraryError>] {
        get { lock.withLock { _createResults } }
        set { lock.withLock { _createResults = newValue } }
    }

    var creations: [ItineraryCreation] { lock.withLock { _creations } }
    var pageCalls: [String?] { lock.withLock { _pageCalls } }
    var detailCalls: [ItineraryID] { lock.withLock { _detailCalls } }
    var renameCalls: [(ItineraryID, String)] { lock.withLock { _renameCalls } }
    var deleteCalls: [ItineraryID] { lock.withLock { _deleteCalls } }

    /// How `rename` and `delete` end (a rename answers the scripted detail renamed);
    /// `offline` until scripted.
    func setChangeResult(_ result: Result<Void, ItineraryError>) {
        lock.withLock { _changeResult = result }
    }

    /// Answers of the next `update` calls, in order; the last one repeats.
    var updateResults: [Result<ItineraryDetail, ItineraryError>] {
        get { lock.withLock { _updateResults } }
        set { lock.withLock { _updateResults = newValue } }
    }

    var updates: [ItineraryCreation] { lock.withLock { _updates } }
    var savedItineraryCalls: [ItineraryID] { lock.withLock { _savedCalls } }

    /// The Waypoints and Legs answered for `id`; an unscripted id answers `offline`.
    func setSavedItinerary(_ result: Result<SavedItinerary, ItineraryError>, for id: ItineraryID) {
        lock.withLock { _saved[id] = result }
    }

    /// The detail answered for `id`; an unscripted id answers `offline`.
    func setDetail(_ result: Result<ItineraryDetail, ItineraryError>, for id: ItineraryID) {
        lock.withLock { _details[id] = result }
    }

    /// The page answered for `cursor`; an unscripted cursor answers an empty last page.
    func setPage(_ result: Result<ItineraryPage, ItineraryError>, for cursor: String? = nil) {
        lock.withLock { _pages[cursor] = result }
    }

    func hold() {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        lock.withLock {
            gate = stream
            gateContinuation = continuation
        }
    }

    func release() {
        lock.withLock { gateContinuation }?.finish()
    }

    func create(_ creation: ItineraryCreation) async throws(ItineraryError) -> CreatedItinerary {
        let result = lock.withLock {
            _creations.append(creation)
            return _createResults.count > 1 ? _createResults.removeFirst() : _createResults.first
        }
        guard let result else { throw .server(code: "unscripted") }
        return try result.get()
    }

    func page(cursor: String?) async throws(ItineraryError) -> ItineraryPage {
        let gate = lock.withLock {
            _pageCalls.append(cursor)
            return self.gate
        }
        if let gate {
            for await _ in gate {}
        }
        let result = lock.withLock { _pages[cursor] } ?? .success(ItineraryPage(items: [], nextCursor: nil))
        return try result.get()
    }

    func detail(id: ItineraryID) async throws(ItineraryError) -> ItineraryDetail {
        let result = lock.withLock {
            _detailCalls.append(id)
            return _details[id]
        }
        return try (result ?? .failure(.offline)).get()
    }

    func rename(id: ItineraryID, to name: String) async throws(ItineraryError) -> ItineraryDetail {
        let (result, detail) = lock.withLock {
            _renameCalls.append((id, name))
            return (_changeResult, _details[id])
        }
        try result.get()
        var renamed = try (detail ?? .failure(.notFound)).get()
        renamed.name = name
        return renamed
    }

    func delete(id: ItineraryID) async throws(ItineraryError) {
        let result = lock.withLock {
            _deleteCalls.append(id)
            return _changeResult
        }
        try result.get()
    }

    func savedItinerary(id: ItineraryID) async throws(ItineraryError) -> SavedItinerary {
        let result = lock.withLock {
            _savedCalls.append(id)
            return _saved[id]
        }
        return try (result ?? .failure(.offline)).get()
    }

    func update(_ edit: ItineraryCreation) async throws(ItineraryError) -> ItineraryDetail {
        let result = lock.withLock {
            _updates.append(edit)
            return _updateResults.count > 1 ? _updateResults.removeFirst() : _updateResults.first
        }
        guard let result else { throw .server(code: "unscripted") }
        return try result.get()
    }
}
