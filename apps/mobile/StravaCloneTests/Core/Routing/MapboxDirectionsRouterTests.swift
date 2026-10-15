import Foundation
import Testing
@testable import StravaClone

/// Own `URLProtocol` stub, like `APIFeedRepositoryTests`: suites run in parallel.
private final class DirectionsURLProtocolStub: URLProtocol, @unchecked Sendable {
    static let handler = Locked<(@Sendable (URLRequest) throws -> (Int, Data))?>(nil)
    static let requests = Locked<[URLRequest]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.value.append(request)
        do {
            let (status, body) = try Self.handler.value?(request) ?? (500, Data())
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct MapboxDirectionsRouterTests {
    private let a = Coordinate(latitude: 45.900_2, longitude: 6.120_3)
    private let b = Coordinate(latitude: 45.901_1, longitude: 6.121_4)
    private let c = Coordinate(latitude: 45.902_3, longitude: 6.122_1)

    /// Two Legs; the first one loops back through the junction before reaching it:
    /// A (45.9, 6.12) → B (45.901, 6.121) → (45.902, 6.121) → B | B → C (45.902, 6.122).
    private let twoLegsJSON = Data("""
    {
      "code": "Ok",
      "routes": [{
        "geometry": "_mopvA_cptJo}@o}@o}@?n}@?o}@o}@",
        "distance": 482.0,
        "legs": [
          { "distance": 404.7, "annotation": { "distance": [137.3, 111.2, 111.2] } },
          { "distance": 137.3, "annotation": { "distance": [137.3] } }
        ]
      }],
      "waypoints": [
        { "name": "", "location": [6.12, 45.9] },
        { "name": "Chemin", "location": [6.121, 45.901] },
        { "name": "", "location": [6.122, 45.902] }
      ]
    }
    """.utf8)

    private func makeRouter(token: String = "pk.test") -> MapboxDirectionsRouter {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DirectionsURLProtocolStub.self]
        DirectionsURLProtocolStub.requests.value = []
        return MapboxDirectionsRouter(accessToken: token, session: URLSession(configuration: configuration))
    }

    private func respond(_ status: Int, _ body: String) {
        DirectionsURLProtocolStub.handler.value = { _ in (status, Data(body.utf8)) }
    }

    @Test func requestsTheDirectionsAPIWithSnappingAndFullPolyline6Geometry() async throws {
        let router = makeRouter()
        let json = twoLegsJSON
        DirectionsURLProtocolStub.handler.value = { _ in (200, json) }

        _ = try await router.path(through: [a, b, c], profile: .walking)

        let request = try #require(DirectionsURLProtocolStub.requests.value.first)
        #expect(request.httpMethod == "GET")
        let components = try #require(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
        #expect(components.host == "api.mapbox.com")
        #expect(components.path == "/directions/v5/mapbox/walking/6.120300,45.900200;6.121400,45.901100;6.122100,45.902300")
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        #expect(query["geometries"] == "polyline6")
        #expect(query["overview"] == "full")
        #expect(query["radiuses"] == "200;200;200")
        #expect(query["annotations"] == "distance")
        #expect(query["access_token"] == "pk.test")
    }

    @Test func constrainsTheFirstWaypointToTheGivenBearing() async throws {
        let router = makeRouter()
        let json = twoLegsJSON
        DirectionsURLProtocolStub.handler.value = { _ in (200, json) }

        _ = try await router.path(through: [a, b, c], profile: .walking, startBearing: Bearing(degrees: 87, tolerance: 45))

        let url = try #require(DirectionsURLProtocolStub.requests.value.first?.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.first { $0.name == "bearings" }?.value == "87,45;;")
    }

    @Test func sendsNoBearingsWhenNoneIsGiven() async throws {
        let router = makeRouter()
        let json = twoLegsJSON
        DirectionsURLProtocolStub.handler.value = { _ in (200, json) }

        _ = try await router.path(through: [a, b, c], profile: .walking)

        let url = try #require(DirectionsURLProtocolStub.requests.value.first?.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(!items.contains { $0.name == "bearings" })
    }

    @Test(arguments: [RoutingProfile.walking, .cycling])
    func usesTheProfileOfTheSportCategory(profile: RoutingProfile) async throws {
        let router = makeRouter()
        let json = twoLegsJSON
        DirectionsURLProtocolStub.handler.value = { _ in (200, json) }

        _ = try await router.path(through: [a, b, c], profile: profile)

        let url = try #require(DirectionsURLProtocolStub.requests.value.first?.url)
        #expect(url.path.hasPrefix("/directions/v5/mapbox/\(profile.rawValue)/"))
    }

    @Test func decodesTheSnappedWaypointsAndOneGeometryPerLeg() async throws {
        let router = makeRouter()
        let json = twoLegsJSON
        DirectionsURLProtocolStub.handler.value = { _ in (200, json) }

        let path = try await router.path(through: [a, b, c], profile: .walking)

        #expect(path.waypoints == [
            Coordinate(latitude: 45.9, longitude: 6.12),
            Coordinate(latitude: 45.901, longitude: 6.121),
            Coordinate(latitude: 45.902, longitude: 6.122),
        ])
        let junction = Coordinate(latitude: 45.901, longitude: 6.121)
        #expect(path.legs == [
            [Coordinate(latitude: 45.9, longitude: 6.12), junction, Coordinate(latitude: 45.902, longitude: 6.121), junction],
            [junction, Coordinate(latitude: 45.902, longitude: 6.122)],
        ])
    }

    @Test func withoutAnnotationsTheGeometryIsSplitAtTheSnappedWaypoints() async throws {
        let router = makeRouter()
        respond(200, """
        {
          "code": "Ok",
          "routes": [{ "geometry": "_mopvA_cptJ?o}@o}@?o}@??o}@", "legs": [{}, {}] }],
          "waypoints": [{ "location": [6.12, 45.9] }, { "location": [6.121, 45.901] }, { "location": [6.122, 45.902] }]
        }
        """)

        let path = try await router.path(through: [a, b, c], profile: .walking)

        #expect(path.legs.map(\.count) == [3, 3])
        #expect(path.legs[0].last == Coordinate(latitude: 45.901, longitude: 6.121))
        #expect(path.legs[1].first == Coordinate(latitude: 45.901, longitude: 6.121))
    }

    @Test(arguments: [
        (200, #"{"code":"NoRoute","message":"No route found"}"#),
        (200, #"{"code":"NoSegment","message":"No road segment could be matched"}"#),
        (422, #"{"code":"NoSegment","message":"No road segment could be matched"}"#),
        (422, #"{"code":"InvalidInput","message":"Route exceeds maximum distance limitation"}"#),
    ])
    func classifiesAMissingPath(status: Int, body: String) async {
        let router = makeRouter()
        respond(status, body)

        await #expect(throws: RoutingError.noPath) {
            try await router.path(through: [a, b], profile: .walking)
        }
    }

    @Test func classifiesA429AsSaturated() async {
        let router = makeRouter()
        respond(429, #"{"message":"Too Many Requests"}"#)

        await #expect(throws: RoutingError.rateLimited) {
            try await router.path(through: [a, b], profile: .cycling)
        }
    }

    @Test(arguments: [500, 502, 503, 504])
    func classifiesServerErrorsAsTemporary(status: Int) async {
        let router = makeRouter()
        respond(status, "")

        await #expect(throws: RoutingError.temporary) {
            try await router.path(through: [a, b], profile: .walking)
        }
    }

    @Test(arguments: [URLError.Code.notConnectedToInternet, .timedOut, .networkConnectionLost])
    func classifiesNetworkFailuresAsTemporary(code: URLError.Code) async {
        let router = makeRouter()
        DirectionsURLProtocolStub.handler.value = { _ in throw URLError(code) }

        await #expect(throws: RoutingError.temporary) {
            try await router.path(through: [a, b], profile: .walking)
        }
    }

    @Test func classifiesAnUnreadableAnswerAsTemporary() async {
        let router = makeRouter()
        respond(200, "<html>oops</html>")

        await #expect(throws: RoutingError.temporary) {
            try await router.path(through: [a, b], profile: .walking)
        }
    }
}
