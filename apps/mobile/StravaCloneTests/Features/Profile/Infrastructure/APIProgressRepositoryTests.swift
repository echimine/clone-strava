import Foundation
import Testing
@testable import StravaClone

/// Own `URLProtocol` stub, like `APIAthleteRepositoryTests`: suites run in parallel.
private final class ProgressURLProtocolStub: URLProtocol, @unchecked Sendable {
    static let handler = Locked<(@Sendable (URLRequest) -> (Int, Data))?>(nil)
    static let requests = Locked<[URLRequest]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.value.append(request)
        let (status, body) = Self.handler.value?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct APIProgressRepositoryTests {
    private func makeRepository() -> APIProgressRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProgressURLProtocolStub.self]
        let authSession = AuthSession(service: "test.progress.\(UUID())")
        authSession.clear()
        ProgressURLProtocolStub.requests.value = []
        return APIProgressRepository(
            apiClient: APIClient(
                baseURL: URL(string: "https://api.test")!,
                session: URLSession(configuration: configuration),
                authSession: authSession
            )
        )
    }

    private func respond(_ status: Int, _ json: String) {
        let body = Data(json.utf8)
        ProgressURLProtocolStub.handler.value = { _ in (status, body) }
    }

    @Test func decodesMyProgressForOneSport() async throws {
        let repository = makeRepository()
        respond(200, """
        {
          "sportTypeCode": "run",
          "weeks": [
            { "weekStart": "2026-10-26", "distanceM": 0, "elevationGainM": 0, "movingTimeS": 0, "activityCount": 0 },
            { "weekStart": "2026-11-02", "distanceM": 21000.5, "elevationGainM": 120, "movingTimeS": 7200, "activityCount": 2 }
          ],
          "streak": { "weeks": 5, "activeDays": ["2026-11-01", "2026-11-03"] }
        }
        """)

        let progress = try await repository.progress(sport: .run)

        let request = try #require(ProgressURLProtocolStub.requests.value.last)
        let components = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
        #expect(components.path == "/v1/me/progress")
        #expect(components.queryItems == [URLQueryItem(name: "sport", value: "run")])
        #expect(progress == AthleteProgress(
            sport: .run,
            weeks: [
                WeekProgress(
                    weekStart: CalendarDay(year: 2026, month: 10, day: 26),
                    distance: .zero,
                    elevationGain: 0,
                    movingTime: .zero,
                    activityCount: 0
                ),
                WeekProgress(
                    weekStart: CalendarDay(year: 2026, month: 11, day: 2),
                    distance: Distance(meters: 21_000.5),
                    elevationGain: 120,
                    movingTime: .seconds(7_200),
                    activityCount: 2
                ),
            ],
            streakWeeks: 5,
            activeDays: [CalendarDay(year: 2026, month: 11, day: 1), CalendarDay(year: 2026, month: 11, day: 3)]
        ))
    }

    @Test func anUnknownSportIsAServerError() async {
        let repository = makeRepository()
        respond(422, #"{ "error": { "code": "validation_error", "message": "Unknown sport" } }"#)

        await #expect(throws: AthleteError.server(code: "validation_error")) {
            try await repository.progress(sport: .other("curling"))
        }
    }
}
