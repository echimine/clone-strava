import Foundation

/// `ItineraryRouter` and `ReturnPathRouter` on the Mapbox Directions REST API (ADR-030 §2,
/// ADR-031 §7), with `URLSession` and `Codable` and no SDK. Uses the token dedicated to
/// Itineraries, never the map's token.
struct MapboxDirectionsRouter: ItineraryRouter, ReturnPathRouter {
    /// A Waypoint further than this from any path is not snapped: the Leg has no path.
    static let snapRadiusMeters = 200

    let accessToken: String
    var session: URLSession = .shared
    var baseURL = URL(string: "https://api.mapbox.com")!

    func path(through waypoints: [Coordinate], profile: RoutingProfile, startBearing: Bearing?) async throws -> RoutedPath {
        var components = components(through: waypoints, profile: profile, startBearing: startBearing)
        components.queryItems?.append(contentsOf: [
            URLQueryItem(name: "radiuses", value: Array(repeating: "\(Self.snapRadiusMeters)", count: waypoints.count).joined(separator: ";")),
            // Segment distances per Leg: their count tells where each Leg starts in the geometry.
            URLQueryItem(name: "annotations", value: "distance"),
        ])
        let body = try await send(components)
        guard let path = Self.routedPath(from: body, waypointCount: waypoints.count) else {
            throw RoutingError.temporary
        }
        return path
    }

    /// Two points snapped however far they are from a path (`radiuses=unlimited`), no
    /// turn-by-turn steps.
    func returnPath(
        from position: Coordinate,
        to destination: Coordinate,
        profile: RoutingProfile,
        bearing: Bearing?
    ) async throws -> RoutedReturnPath {
        var components = components(through: [position, destination], profile: profile, startBearing: bearing)
        components.queryItems?.append(contentsOf: [
            URLQueryItem(name: "radiuses", value: "unlimited;unlimited"),
            URLQueryItem(name: "steps", value: "false"),
        ])
        let body = try await send(components)
        guard let route = body.routes?.first, let distance = route.distance else { throw RoutingError.temporary }
        let path = EncodedPolyline(value: route.geometry, precision: 6).decode()
        guard path.count >= 2 else { throw RoutingError.temporary }
        return RoutedReturnPath(path: path, distance: Distance(meters: distance))
    }

    /// The decoded `Ok` answer, or the `RoutingError` its status and code mean.
    private func send(_ components: URLComponents) async throws -> DirectionsResponse {
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw RoutingError.temporary
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = try? JSONDecoder().decode(DirectionsResponse.self, from: data)
        switch (status, body?.code) {
        case (_, "NoRoute"), (_, "NoSegment"), (422, _):
            throw RoutingError.noPath
        case (429, _):
            throw RoutingError.rateLimited
        case (200, "Ok"):
            guard let body else { throw RoutingError.temporary }
            return body
        default:
            throw RoutingError.temporary
        }
    }

    private func components(through waypoints: [Coordinate], profile: RoutingProfile, startBearing: Bearing?) -> URLComponents {
        let coordinates = waypoints
            .map { String(format: "%.6f,%.6f", $0.longitude, $0.latitude) }
            .joined(separator: ";")
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/directions/v5/mapbox/\(profile.rawValue)/\(coordinates)"
        components.queryItems = [
            URLQueryItem(name: "geometries", value: "polyline6"),
            URLQueryItem(name: "overview", value: "full"),
            URLQueryItem(name: "access_token", value: accessToken),
        ]
        if let startBearing {
            // One `angle,range` per Waypoint, empty for the ones left free.
            let first = "\(Int(startBearing.degrees.rounded())),\(Int(startBearing.tolerance.rounded()))"
            let bearings = [first] + Array(repeating: "", count: waypoints.count - 1)
            components.queryItems?.append(URLQueryItem(name: "bearings", value: bearings.joined(separator: ";")))
        }
        return components
    }

    // MARK: Decoding

    private static func routedPath(from body: DirectionsResponse, waypointCount: Int) -> RoutedPath? {
        guard
            let route = body.routes?.first,
            let snapped = body.waypoints?.compactMap(\.coordinate), snapped.count == waypointCount,
            route.legs.count == waypointCount - 1
        else { return nil }
        let geometry = EncodedPolyline(value: route.geometry, precision: 6).decode()
        guard geometry.count >= 2, let legs = splitByAnnotations(geometry, legs: route.legs)
            ?? splitAtWaypoints(geometry, waypoints: snapped)
        else { return nil }
        return RoutedPath(waypoints: snapped, legs: legs)
    }

    /// Leg *n* has as many segments as distance annotations; consecutive Legs share a point.
    private static func splitByAnnotations(_ geometry: [Coordinate], legs: [DirectionsResponse.Leg]) -> [[Coordinate]]? {
        let counts = legs.compactMap { $0.annotation?.distance?.count }
        guard counts.count == legs.count, counts.allSatisfy({ $0 > 0 }), counts.reduce(0, +) + 1 == geometry.count else {
            return nil
        }
        var start = 0
        return counts.map { count in
            defer { start += count }
            return Array(geometry[start ... start + count])
        }
    }

    /// Fallback: cuts at the geometry point nearest to each intermediate snapped Waypoint.
    private static func splitAtWaypoints(_ geometry: [Coordinate], waypoints: [Coordinate]) -> [[Coordinate]]? {
        var cuts = [0]
        for waypoint in waypoints.dropFirst().dropLast() {
            let from = cuts.last!
            guard let cut = geometry.indices.dropFirst(from).min(by: {
                geometry[$0].distance(to: waypoint) < geometry[$1].distance(to: waypoint)
            }) else { return nil }
            cuts.append(cut)
        }
        cuts.append(geometry.count - 1)
        return zip(cuts, cuts.dropFirst()).map { Array(geometry[$0 ... $1]) }
    }
}

/// Subset of the Directions API response that the editor needs.
private struct DirectionsResponse: Decodable {
    struct Route: Decodable {
        let geometry: String
        /// Meters.
        let distance: Double?
        let legs: [Leg]
    }

    struct Leg: Decodable {
        struct Annotation: Decodable {
            let distance: [Double]?
        }

        let annotation: Annotation?
    }

    struct Waypoint: Decodable {
        /// `[longitude, latitude]`.
        let location: [Double]

        var coordinate: Coordinate? {
            location.count == 2 ? Coordinate(latitude: location[1], longitude: location[0]) : nil
        }
    }

    let code: String
    let routes: [Route]?
    let waypoints: [Waypoint]?
}
