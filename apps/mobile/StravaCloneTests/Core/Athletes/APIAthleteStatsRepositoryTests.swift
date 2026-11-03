import Foundation
import Testing
@testable import StravaClone

/// Own `URLProtocol` stub, like `APIAthleteRepositoryTests`: suites run in parallel.
private final class StatsURLProtocolStub: URLProtocol, @unchecked Sendable {
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
struct APIAthleteStatsRepositoryTests {
    private let athleteId = "0b6f2f0e-5b1c-4f3e-9d43-3c2a1b0e9f01"

    private func makeRepository() -> APIAthleteStatsRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StatsURLProtocolStub.self]
        let authSession = AuthSession(service: "test.athleteStats.\(UUID())")
        authSession.clear()
        StatsURLProtocolStub.requests.value = []
        return APIAthleteStatsRepository(
            apiClient: APIClient(
                baseURL: URL(string: "https://api.test")!,
                session: URLSession(configuration: configuration),
                authSession: authSession
            )
        )
    }

    private func respond(_ status: Int, _ json: String) {
        let body = Data(json.utf8)
        StatsURLProtocolStub.handler.value = { _ in (status, body) }
    }

    private func lastRequestComponents() throws -> URLComponents {
        let request = try #require(StatsURLProtocolStub.requests.value.last)
        return try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
    }

    @Test func decodesTheStatisticsOfOneSport() async throws {
        let repository = makeRepository()
        respond(200, """
        {
          "sportTypeCode": "ride",
          "recent": { "weeks": 4, "activitiesPerWeek": 1.5, "movingTimeSPerWeek": 3600, "distanceMPerWeek": 12000 },
          "yearToDate": { "activityCount": 40, "movingTimeS": 90000, "distanceM": 412345.6, "elevationGainM": 3000 },
          "allTime": { "activityCount": 80, "distanceM": 900000, "elevationGainM": 7000 }
        }
        """)

        let stats = try await repository.stats(of: athleteId, sport: .ride)

        let components = try lastRequestComponents()
        #expect(components.path == "/v1/athletes/\(athleteId)/stats")
        #expect(components.queryItems == [URLQueryItem(name: "sport", value: "ride")])
        #expect(stats == AthleteStats(
            sport: .ride,
            recent: .init(activitiesPerWeek: 1.5, movingTimePerWeek: .seconds(3600), distancePerWeek: Distance(meters: 12_000)),
            yearToDate: .init(
                activityCount: 40,
                movingTime: .seconds(90_000),
                distance: Distance(meters: 412_345.6),
                elevationGain: 3000
            ),
            allTime: .init(activityCount: 80, distance: Distance(meters: 900_000), elevationGain: 7000)
        ))
    }

    @Test func allSportsSendsNoSportAndHasNoSport() async throws {
        let repository = makeRepository()
        respond(200, """
        {
          "recent": { "weeks": 4, "activitiesPerWeek": 0, "movingTimeSPerWeek": 0, "distanceMPerWeek": 0 },
          "yearToDate": { "activityCount": 0, "movingTimeS": 0, "distanceM": 0, "elevationGainM": 0 },
          "allTime": { "activityCount": 0, "distanceM": 0, "elevationGainM": 0 }
        }
        """)

        let stats = try await repository.stats(of: athleteId, sport: nil)

        #expect(try lastRequestComponents().queryItems == nil)
        #expect(stats.sport == nil)
        #expect(stats.allTime.activityCount == 0)
    }

    @Test func anUnknownAthleteIsNotFound() async {
        let repository = makeRepository()
        respond(404, #"{ "error": { "code": "athlete_not_found", "message": "Not found" } }"#)

        await #expect(throws: AthleteError.notFound) {
            try await repository.stats(of: athleteId, sport: .run)
        }
    }
}
