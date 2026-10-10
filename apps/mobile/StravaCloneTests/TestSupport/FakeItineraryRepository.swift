import Foundation
@testable import StravaClone

/// Hand-written `ItineraryRepository` (ADR-025 §3): scripted answers, recorded calls.
/// `hold()` suspends `page` calls until `release()`, to observe a resync in flight.
final class FakeItineraryRepository: ItineraryRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var _createResults: [Result<ItineraryDetail, ItineraryError>] = []
    private var _pages: [String?: Result<ItineraryPage, ItineraryError>] = [:]
    private var _creations: [ItineraryCreation] = []
    private var _pageCalls: [String?] = []
    private var gate: AsyncStream<Void>?
    private var gateContinuation: AsyncStream<Void>.Continuation?

    /// Answers of the next `create` calls, in order; the last one repeats.
    var createResults: [Result<ItineraryDetail, ItineraryError>] {
        get { lock.withLock { _createResults } }
        set { lock.withLock { _createResults = newValue } }
    }

    var creations: [ItineraryCreation] { lock.withLock { _creations } }
    var pageCalls: [String?] { lock.withLock { _pageCalls } }

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

    func create(_ creation: ItineraryCreation) async throws(ItineraryError) -> ItineraryDetail {
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
}
