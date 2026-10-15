import Foundation
@testable import StravaClone

/// Own `URLProtocol` stub for the Activity creation flow (suites run in parallel): answers
/// each request from a scripted handler, records every request with its body.
final class ActivityURLProtocolStub: URLProtocol, @unchecked Sendable {
    enum Answer {
        case status(Int, String = "")
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
            client?.urlProtocol(self, didLoad: Data(body.utf8))
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

/// A local Activity saved from a finished Recording (real GRDB in memory), and an
/// `ActivitySender` over the real API adapter and a stubbed network.
struct ActivitySenderHarness: Sendable {
    static let start = Date(timeIntervalSince1970: 1_792_047_600)
    /// The clock of the sender: one hour after Start.
    static let now = start.addingTimeInterval(3_600)

    let database: AppDatabase
    let store: GRDBLocalActivityStore
    let refresher: FakeSessionRefresher
    let id: ActivityID

    init(refreshSucceeds: Bool = true, database: AppDatabase? = nil, id: ActivityID = ActivityID()) throws {
        self.database = try database ?? AppDatabase.inMemory()
        store = GRDBLocalActivityStore(database: self.database, now: { Self.now })
        refresher = FakeSessionRefresher(succeeds: refreshSucceeds)
        self.id = id
    }

    static func resetNetwork() {
        ActivityURLProtocolStub.requests.value = []
        ActivityURLProtocolStub.handler.value = nil
    }

    var requests: [URLRequest] { ActivityURLProtocolStub.requests.value }

    /// "POST /v1/activities", "PUT bucket.test/…": the requests sent, in order.
    var requestLines: [String] {
        requests.map { request in
            let url = request.url!
            return url.host == "bucket.test" ? "PUT bucket" : "\(request.httpMethod ?? "") \(url.path)"
        }
    }

    @MainActor
    func makeSender(backoff: RetryBackoff = RetryBackoff(initialDelay: .seconds(2), maxDelay: .seconds(300))) -> ActivitySender {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ActivityURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let authSession = AuthSession(service: "test.activity-sender.\(UUID())")
        authSession.clear()
        let server = APIActivityServer(
            apiClient: APIClient(baseURL: URL(string: "https://api.test")!, session: session, authSession: authSession),
            uploadSession: session
        )
        return ActivitySender(server: server, store: store, sessionRefresher: refresher, backoff: backoff, now: { Self.now })
    }

    /// A 10-minute run with a Pause, finished and saved: 3 points, one finished Pause.
    func saveRecordedActivity() async throws {
        let recordings = GRDBRecordingRepository(database: database)
        var recording = Recording(id: id, sport: .run, startedAt: Self.start)
        try await recordings.create(recording)
        try await recordings.append(sample(0, north: 0), to: id)
        try await recordings.append(sample(60, north: 150), to: id)
        recording.pause(at: Self.start.addingTimeInterval(60))
        recording.resume(at: Self.start.addingTimeInterval(120))
        try await recordings.save(recording)
        try await recordings.append(sample(600, north: 1_500), to: id)
        recording.pause(at: Self.start.addingTimeInterval(600))
        recording.finish()
        try await recordings.save(recording)
        try await store.saveRecorded(LocalActivity(
            id: id,
            sport: .run,
            title: "Course à pied le matin",
            visibility: .followers,
            startedAt: Self.start,
            endedAt: Self.start.addingTimeInterval(600),
            distance: Distance(meters: 1_500),
            movingTimeS: 540,
            elapsedTimeS: 600
        ))
    }

    private func sample(_ seconds: TimeInterval, north: Double) -> LocationSample {
        LocationSample(
            coordinate: Coordinate(latitude: 45.764, longitude: 4.8357).offset(northMeters: north),
            altitude: 170,
            horizontalAccuracy: 5,
            speed: 2.5,
            timestamp: Self.start.addingTimeInterval(seconds)
        )
    }

    // MARK: - Server answers

    static func iso(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }

    func summary(_ status: String) -> String {
        #"{"id":"\#(id)","sportTypeCode":"run","visibility":"followers","processingStatus":"\#(status)"}"#
    }

    /// `POST /v1/activities` `201` with a URL valid until `expiresAt` (15 min by default).
    func created(expiresAt: Date = now.addingTimeInterval(900), signature: String = "first") -> ActivityURLProtocolStub.Answer {
        .status(201, #"{"activity":\#(summary("pending")),"upload":{"uploadUrl":"https://bucket.test/trace.json.gz?sig=\#(signature)","expiresAt":"\#(Self.iso(expiresAt))"}}"#)
    }

    func renewed(signature: String = "renewed") -> ActivityURLProtocolStub.Answer {
        .status(200, #"{"uploadUrl":"https://bucket.test/trace.json.gz?sig=\#(signature)","expiresAt":"\#(Self.iso(Self.now.addingTimeInterval(900)))"}"#)
    }

    func completed() -> ActivityURLProtocolStub.Answer {
        .status(202, #"{"activity":\#(summary("processing"))}"#)
    }

    func detail(_ status: String, error: String? = nil) -> ActivityURLProtocolStub.Answer {
        let processingError = error.map { #","processingError":"\#($0)""# } ?? ""
        return .status(200, #"{"id":"\#(id)","sportTypeCode":"run","title":"Course à pied le matin","startedAt":"\#(Self.iso(Self.start))","endedAt":"\#(Self.iso(Self.start.addingTimeInterval(600)))","visibility":"followers","processingStatus":"\#(status)"\#(processingError),"stats":null}"#)
    }

    static func refused(_ status: Int, _ code: String) -> ActivityURLProtocolStub.Answer {
        .status(status, #"{"error":{"code":"\#(code)","message":"Refused"}}"#)
    }

    /// Routes each request to `answer(step)`: "create", "upload-url", "upload", "complete", "detail".
    static func route(_ answer: @escaping @Sendable (String) -> ActivityURLProtocolStub.Answer) {
        ActivityURLProtocolStub.handler.value = { request in
            let url = request.url!
            if url.host == "bucket.test" { return answer("upload") }
            if url.path.hasSuffix("/upload-url") { return answer("upload-url") }
            if url.path.hasSuffix("/complete") { return answer("complete") }
            if request.httpMethod == "GET" { return answer("detail") }
            return answer("create")
        }
    }
}
