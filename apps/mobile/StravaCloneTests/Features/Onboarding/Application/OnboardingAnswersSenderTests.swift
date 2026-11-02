import Foundation
import Testing
@testable import StravaClone

/// Own `URLProtocol` stub (suites run in parallel): answers a status, or no network at all.
private final class AnswersURLProtocolStub: URLProtocol, @unchecked Sendable {
    enum Answer {
        case status(Int)
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
        case .status(let status):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data())
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

/// Sending the Onboarding answers after sign-in (ADR-035 §5): the real API adapter over a
/// stubbed network, the real GRDB draft and `sync_operation` queue in memory.
@MainActor
@Suite(.serialized)
struct OnboardingAnswersSenderTests {
    private struct Harness {
        let sender: OnboardingAnswersSender
        let drafts: GRDBOnboardingDraftRepository
        let queue: SyncQueueState
        let refresher: FakeSessionRefresher
        let sleeper: ManualSleeper
        let clock: Locked<Date>

        var requests: [URLRequest] { AnswersURLProtocolStub.requests.value }
    }

    private func make(refreshSucceeds: Bool = true) async throws -> Harness {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AnswersURLProtocolStub.self]
        let authSession = AuthSession(service: "test.onboarding-answers.\(UUID())")
        authSession.clear()
        AnswersURLProtocolStub.requests.value = []
        AnswersURLProtocolStub.handler.value = nil
        let database = try AppDatabase.inMemory()
        let drafts = GRDBOnboardingDraftRepository(database: database)
        try await drafts.save(Self.completedDraft)
        let refresher = FakeSessionRefresher(succeeds: refreshSucceeds)
        let sleeper = ManualSleeper()
        let clock = Locked(Date.fixture())
        let sender = OnboardingAnswersSender(
            server: APIOnboardingAnswersServer(apiClient: APIClient(
                baseURL: URL(string: "https://api.test")!,
                session: URLSession(configuration: configuration),
                authSession: authSession
            )),
            drafts: drafts,
            queue: GRDBOnboardingSubmissionQueue(database: database),
            sessionRefresher: refresher,
            backoff: RetryBackoff(initialDelay: .seconds(2), maxDelay: .seconds(300)),
            now: { clock.value },
            sleep: sleeper.sleep
        )
        return Harness(sender: sender, drafts: drafts, queue: SyncQueueState(database: database), refresher: refresher, sleeper: sleeper, clock: clock)
    }

    private func answer(_ handler: @escaping @Sendable (URLRequest) -> AnswersURLProtocolStub.Answer) {
        AnswersURLProtocolStub.handler.value = handler
    }

    /// The draft as the Onboarding leaves it on the account screen.
    private static let completedDraft: OnboardingDraft = {
        var answers = OnboardingAnswers()
        answers.firstName = " Camille "
        answers.lastName = "Martin"
        answers.birthDate = CalendarDay(year: 1994, month: 3, day: 9)
        answers.gender = .nonBinary
        answers.sports = [.ride, .run]
        answers.goals = [.health, .discoverRoutes]
        answers.level = .intermediate
        return OnboardingDraft(answers: answers, step: .account)
    }()

    private func body(_ request: URLRequest) throws -> [String: AnyHashable] {
        let data = try #require(request.httpBody)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: AnyHashable])
    }

    // MARK: Sent at once

    @Test func answersAcceptedAtOnceDeleteTheDraftAndQueueNothing() async throws {
        let harness = try await make()
        answer { _ in .status(204) }

        await harness.sender.submit()

        let request = try #require(harness.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/v1/me/onboarding-answers")
        #expect(try body(request) == [
            "firstName": "Camille", "lastName": "Martin", "birthDate": "1994-03-09", "gender": "non_binary",
            "sportCodes": ["ride", "run"], "goals": ["health", "discover_routes"], "level": "intermediate",
        ])
        #expect(try await harness.drafts.load() == nil)
        #expect(await harness.queue.pendingCount() == 0)
    }

    // MARK: Network failure, then the retry

    @Test func answersSentOfflineWaitInTheQueueThenTheRetryDeletesDraftAndOperation() async throws {
        let harness = try await make()
        answer { _ in .offline }

        await harness.sender.submit()

        #expect(await harness.queue.pendingCount() == 1)
        #expect(try await harness.drafts.load() == Self.completedDraft)
        #expect(harness.sleeper.requested == [.seconds(2)])

        answer { _ in .status(204) }
        harness.clock.value = .fixture().addingTimeInterval(2)
        harness.sleeper.wakeAll()

        #expect(await eventually { await harness.queue.pendingCount() == 0 })
        #expect(try await harness.drafts.load() == nil)
        #expect(harness.requests.count == 2)
    }

    @Test func aServerErrorIsRetriedLaterWithALongerDelayEachTime() async throws {
        let harness = try await make()
        answer { _ in .status(503) }

        await harness.sender.submit()
        harness.clock.value = .fixture().addingTimeInterval(2)
        harness.sleeper.wakeAll()

        #expect(await eventually { harness.sleeper.requested == [.seconds(2), .seconds(4)] })
        #expect(await harness.queue.pendingCount() == 1)
    }

    @Test func theQueueTriggersSendTheWaitingAnswersWithoutWaitingForTheDelay() async throws {
        let harness = try await make()
        answer { _ in .offline }
        await harness.sender.submit()

        answer { _ in .status(204) }
        await harness.sender.send(ignoringBackoff: true)

        #expect(await harness.queue.pendingCount() == 0)
        #expect(try await harness.drafts.load() == nil)
    }

    // MARK: Refused, session expired, sign-out

    @Test func answersRefusedByTheServerAreDroppedWithoutRetry() async throws {
        let harness = try await make()
        answer { _ in .status(422) }

        await harness.sender.submit()

        #expect(await harness.queue.pendingCount() == 0)
        #expect(try await harness.drafts.load() == nil)
        #expect(harness.sleeper.requested.isEmpty)
    }

    @Test func anExpiredSessionIsRefreshedThenTheAnswersAreSentAgain() async throws {
        let harness = try await make()
        let calls = Locked(0)
        answer { _ in
            calls.value += 1
            return .status(calls.value == 1 ? 401 : 204)
        }

        await harness.sender.submit()

        #expect(harness.refresher.calls == 1)
        #expect(harness.requests.count == 2)
        #expect(await harness.queue.pendingCount() == 0)
        #expect(try await harness.drafts.load() == nil)
    }

    @Test func aSessionThatCannotBeRefreshedKeepsTheAnswersQueued() async throws {
        let harness = try await make(refreshSucceeds: false)
        answer { _ in .status(401) }

        await harness.sender.submit()

        #expect(harness.requests.count == 1)
        #expect(await harness.queue.pendingCount() == 1)
        #expect(try await harness.drafts.load() == Self.completedDraft)
    }

    @Test func signingOutDeletesTheDraftAndTheQueuedAnswers() async throws {
        let harness = try await make()
        answer { _ in .offline }
        await harness.sender.submit()

        await harness.sender.clear()

        #expect(await harness.queue.pendingCount() == 0)
        #expect(try await harness.drafts.load() == nil)
        #expect(harness.sleeper.waiting == 0)
    }

    @Test func withoutACompleteDraftNothingIsSentAndTheOperationIsDropped() async throws {
        let harness = try await make()
        try await harness.drafts.delete()

        await harness.sender.submit()

        #expect(harness.requests.isEmpty)
        #expect(await harness.queue.pendingCount() == 0)
    }
}
