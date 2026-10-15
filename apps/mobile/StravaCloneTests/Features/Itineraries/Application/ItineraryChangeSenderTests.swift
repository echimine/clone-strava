import Foundation
import Testing
@testable import StravaClone

/// Own `URLProtocol` stub (suites run in parallel): answers a status, or no network at all.
private final class ChangeURLProtocolStub: URLProtocol, @unchecked Sendable {
    enum Answer {
        case status(Int, Data = Data())
        case offline
    }

    static let handler = Locked<(@Sendable (URLRequest) -> Answer)?>(nil)
    static let requests = Locked<[URLRequest]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var recorded = request
        recorded.httpBody = request.httpBody ?? request.httpBodyStream.map(Self.read)
        Self.requests.value.append(recorded)
        switch Self.handler.value?(recorded) ?? .status(500) {
        case .offline:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        case .status(let status, let body):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// Renames and deletes through the `sync_operation` queue (ADR-008 §3, ADR-030 §8): the real
/// API adapter over a stubbed network, the real GRDB cache and queue in memory.
@MainActor
@Suite(.serialized)
struct ItineraryChangeSenderTests {
    private struct Harness {
        let sender: ItineraryChangeSender
        let cache: GRDBItineraryCache
        let queue: GRDBItineraryChangeQueue
        let refresher: FakeSessionRefresher

        var requests: [URLRequest] { ChangeURLProtocolStub.requests.value }
    }

    private func make(
        refreshSucceeds: Bool = true,
        backoff: RetryBackoff = RetryBackoff(initialDelay: .seconds(2), maxDelay: .seconds(8)),
        now: @escaping @Sendable () -> Date = { .fixture() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = ManualSleeper().sleep
    ) throws -> Harness {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ChangeURLProtocolStub.self]
        let authSession = AuthSession(service: "test.itinerary-changes.\(UUID())")
        authSession.clear()
        ChangeURLProtocolStub.requests.value = []
        ChangeURLProtocolStub.handler.value = nil
        let repository = APIItineraryRepository(apiClient: APIClient(
            baseURL: URL(string: "https://api.test")!,
            session: URLSession(configuration: configuration),
            authSession: authSession
        ))
        let database = try AppDatabase.inMemory()
        let cache = GRDBItineraryCache(database: database)
        let queue = GRDBItineraryChangeQueue(database: database)
        let refresher = FakeSessionRefresher(succeeds: refreshSucceeds)
        let sender = ItineraryChangeSender(
            repository: repository,
            cache: cache,
            queue: queue,
            sessionRefresher: refresher,
            backoff: backoff,
            now: now,
            sleep: sleep
        )
        return Harness(sender: sender, cache: cache, queue: queue, refresher: refresher)
    }

    private func answer(_ handler: @escaping @Sendable (URLRequest) -> ChangeURLProtocolStub.Answer) {
        ChangeURLProtocolStub.handler.value = handler
    }

    private func detailJSON(name: String) -> Data {
        Data("""
        {
          "id": "\(ItineraryID.fixture(1))", "name": "\(name)", "sportTypeCode": "hike",
          "distanceM": 2224, "elevationGainM": 87.5, "elevationSource": "ign",
          "waypoints": [{ "lat": 45.9, "lon": 6.12 }, { "lat": 45.92, "lon": 6.12 }],
          "legs": [{ "mode": "follow", "polyline6": "_mopvA_cptJ_pR?_pR?" }],
          "track": { "polyline6": "_mopvA_cptJ_pR?_pR?", "altitudesM": [446.5, 480, 534] },
          "createdAt": "2026-10-10T07:00:00.500Z", "updatedAt": "2026-10-10T08:05:00.500Z"
        }
        """.utf8)
    }

    private func names(_ cache: GRDBItineraryCache) async throws -> [String] {
        try await cache.summaries(limit: 20).map(\.name)
    }

    // MARK: Offline, then the network comes back

    @Test func anOfflineRenameShowsAtOnceThenIsSentWhenTheNetworkComesBack() async throws {
        let harness = try make()
        try await harness.cache.save(.fixture(1, name: "Nom serveur"), mapPolyline: EncodedPolyline(value: "local"))
        answer { _ in .offline }

        try await harness.sender.rename(id: .fixture(1), to: "  Tour du lac  ")

        #expect(try await names(harness.cache) == ["Tour du lac"])
        #expect(try await harness.queue.pending().map(\.attempts) == [1])

        let json = detailJSON(name: "Tour du lac")
        answer { _ in .status(200, json) }
        await harness.sender.send(ignoringBackoff: true)

        let request = try #require(harness.requests.last)
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.path == "/v1/itineraries/00000000-0000-4000-8000-000000000001")
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String]
        #expect(body == ["name": "Tour du lac"])
        #expect(try await harness.queue.pending().isEmpty)
        #expect(try await harness.cache.summaries(limit: 20).map(\.updatedAt) == [.fixture(minutes: 5)])
        #expect(try await names(harness.cache) == ["Tour du lac"])
    }

    @Test func anOfflineDeleteHidesTheItineraryThenIsSentWhenTheNetworkComesBack() async throws {
        let harness = try make()
        try await harness.cache.replaceSummaries(with: [.fixture(1), .fixture(2)])
        answer { _ in .offline }

        await harness.sender.delete(id: .fixture(1))

        #expect(try await harness.cache.summaries(limit: 20).map(\.id) == [.fixture(2)])

        answer { _ in .status(204) }
        await harness.sender.send(ignoringBackoff: true)

        #expect(harness.requests.last?.httpMethod == "DELETE")
        #expect(try await harness.queue.pending().isEmpty)
        try await harness.cache.replaceSummaries(with: [.fixture(2)])
        #expect(try await harness.cache.summaries(limit: 20).map(\.id) == [.fixture(2)])
    }

    /// `sync_operation` keeps its dates to the millisecond: a change made at 0.6 ms past is
    /// read back due at the next millisecond, and must still leave at once.
    @Test func aChangeLeavesAtOnceWhateverTheSubMillisecondOfTheClock() async throws {
        let harness = try make(now: { Date(timeIntervalSinceReferenceDate: 813_766_111.2236) })
        try await harness.cache.replaceSummaries(with: [.fixture(1)])
        answer { _ in .status(204) }

        await harness.sender.delete(id: .fixture(1))

        #expect(harness.requests.map(\.httpMethod) == ["DELETE"])
        #expect(try await harness.queue.pending().isEmpty)
    }

    @Test func aNameWithoutCharactersIsRefusedBeforeAnything() async throws {
        let harness = try make()

        await #expect(throws: ItinerarySaveIssue.invalidName) {
            try await harness.sender.rename(id: .fixture(1), to: "   ")
        }
        await #expect(throws: ItinerarySaveIssue.invalidName) {
            try await harness.sender.rename(id: .fixture(1), to: String(repeating: "a", count: 101))
        }
        #expect(try await harness.queue.pending().isEmpty)
    }

    /// Two renames then a delete while offline: only the delete is ever sent.
    @Test func coalescedChangesSendOnlyWhatIsLeft() async throws {
        let harness = try make()
        try await harness.cache.replaceSummaries(with: [.fixture(1)])
        answer { _ in .offline }
        try await harness.sender.rename(id: .fixture(1), to: "Premier")
        try await harness.sender.rename(id: .fixture(1), to: "Second")
        await harness.sender.delete(id: .fixture(1))
        ChangeURLProtocolStub.requests.value = []

        answer { _ in .status(204) }
        await harness.sender.send(ignoringBackoff: true)

        #expect(harness.requests.map(\.httpMethod) == ["DELETE"])
    }

    // MARK: Backoff

    @Test func failuresAreRetriedAfterAnExponentialBackoffThatIsCapped() async throws {
        let harness = try make()
        try await harness.cache.replaceSummaries(with: [.fixture(1)])
        let answers = Locked<[ChangeURLProtocolStub.Answer]>([.offline, .status(503), .status(500), .status(502)])
        answer { _ in answers.value.isEmpty ? .status(500) : answers.value.removeFirst() }

        await harness.sender.delete(id: .fixture(1))
        var delays: [TimeInterval] = []
        for _ in 0..<4 {
            let pending = try #require(try await harness.queue.pending().first)
            delays.append(pending.nextAttemptAt.timeIntervalSince(.fixture()))
            await harness.sender.send(ignoringBackoff: true)
        }

        #expect(delays == [2, 4, 8, 8])
        #expect(try await harness.queue.pending().first?.attempts == 5)
    }

    @Test func aChangeIsNotSentAgainBeforeItsBackoffEnds() async throws {
        let harness = try make()
        try await harness.cache.replaceSummaries(with: [.fixture(1)])
        answer { _ in .status(503) }
        await harness.sender.delete(id: .fixture(1))

        await harness.sender.send()

        #expect(harness.requests.count == 1)
    }

    @Test func aPostponedChangeIsSentAgainOnItsOwnOnceDue() async throws {
        let harness = try make(
            backoff: RetryBackoff(initialDelay: .milliseconds(20), maxDelay: .milliseconds(20)),
            now: Date.init,
            sleep: { try await Task.sleep(for: $0) }
        )
        try await harness.cache.replaceSummaries(with: [.fixture(1)])
        let attempts = Locked(0)
        answer { _ in
            attempts.value += 1
            return attempts.value == 1 ? .status(500) : .status(204)
        }

        await harness.sender.delete(id: .fixture(1))
        for _ in 0..<400 {
            if try await harness.queue.pending().isEmpty { break }
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(try await harness.queue.pending().isEmpty)
        #expect(harness.requests.count == 2)
    }

    @Test func cancellingThePassAlsoCancelsTheScheduledRetry() async throws {
        let sleeper = ManualSleeper()
        let harness = try make(sleep: sleeper.sleep)
        try await harness.cache.replaceSummaries(with: [.fixture(1)])
        answer { _ in .offline }
        await harness.sender.delete(id: .fixture(1))
        #expect(await eventually { sleeper.waiting == 1 })

        harness.sender.cancelPass()

        #expect(sleeper.waiting == 0)
        #expect(try await harness.queue.pending().count == 1)
    }

    // MARK: Session

    @Test func a401RefreshesTheSessionThenSendsAgain() async throws {
        let harness = try make()
        try await harness.cache.replaceSummaries(with: [.fixture(1)])
        let attempts = Locked(0)
        answer { _ in
            attempts.value += 1
            return attempts.value == 1 ? .status(401) : .status(204)
        }

        await harness.sender.delete(id: .fixture(1))

        #expect(harness.refresher.calls == 1)
        #expect(harness.requests.map(\.httpMethod) == ["DELETE", "DELETE"])
        #expect(try await harness.queue.pending().isEmpty)
    }

    @Test func aSessionThatCannotBeRefreshedKeepsTheChangeForLater() async throws {
        let harness = try make(refreshSucceeds: false)
        try await harness.cache.replaceSummaries(with: [.fixture(1)])
        answer { _ in .status(401) }

        await harness.sender.delete(id: .fixture(1))

        #expect(harness.requests.count == 1)
        #expect(try await harness.queue.pending().map(\.attempts) == [1])
        #expect(try await harness.cache.summaries(limit: 20).isEmpty)
    }

    // MARK: 404 and refusals

    @Test func aDeleteAnswered404CountsAsDone() async throws {
        let harness = try make()
        try await harness.cache.replaceSummaries(with: [.fixture(1)])
        answer { _ in .status(404, Data(#"{"error":{"code":"not_found","message":"x"}}"#.utf8)) }

        await harness.sender.delete(id: .fixture(1))

        #expect(try await harness.queue.pending().isEmpty)
        try await harness.cache.replaceSummaries(with: [])
        #expect(try await harness.cache.summaries(limit: 20).isEmpty)
    }

    @Test func aRenameAnswered404DropsItAndForgetsTheItinerary() async throws {
        let harness = try make()
        try await harness.cache.replaceSummaries(with: [.fixture(1), .fixture(2)])
        answer { _ in .status(404, Data(#"{"error":{"code":"not_found","message":"x"}}"#.utf8)) }

        try await harness.sender.rename(id: .fixture(1), to: "Disparu")

        #expect(try await harness.queue.pending().isEmpty)
        #expect(try await harness.cache.summaries(limit: 20).map(\.id) == [.fixture(2)])
    }

    @Test func aRenameRefusedByTheServerIsDroppedWithAToastAndTheServerNameComesBack() async throws {
        let harness = try make()
        try await harness.cache.replaceSummaries(with: [.fixture(1, name: "Nom serveur")])
        answer { _ in .status(422, Data(#"{"error":{"code":"validation_error","message":"x"}}"#.utf8)) }
        var refusals = harness.sender.refusals().makeAsyncIterator()

        try await harness.sender.rename(id: .fixture(1), to: "Refusé")

        #expect(await refusals.next() == .rename)
        #expect(try await harness.queue.pending().isEmpty)
        #expect(try await names(harness.cache) == ["Nom serveur"])
        #expect(harness.requests.count == 1)
    }

    @Test func anyOtherClientErrorIsARefusalToo() async throws {
        let harness = try make()
        try await harness.cache.replaceSummaries(with: [.fixture(1, name: "Nom serveur")])
        answer { _ in .status(403) }
        var refusals = harness.sender.refusals().makeAsyncIterator()

        try await harness.sender.rename(id: .fixture(1), to: "Interdit")

        #expect(await refusals.next() == .rename)
        #expect(try await harness.queue.pending().isEmpty)
    }

    // MARK: Sign-out

    @Test func signingOutForgetsThePendingChanges() async throws {
        let harness = try make()
        try await harness.cache.replaceSummaries(with: [.fixture(1), .fixture(2)])
        answer { _ in .offline }
        try await harness.sender.rename(id: .fixture(1), to: "Renommé")
        await harness.sender.delete(id: .fixture(2))
        #expect(await harness.sender.pendingCount() == 2)

        await harness.sender.clear()

        #expect(await harness.sender.pendingCount() == 0)
    }
}
