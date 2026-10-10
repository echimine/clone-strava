import Foundation

/// `APIClient` adapter of `ItineraryRepository` (ADR-030 §6), on the types generated from
/// openapi.json (ADR-026 §5).
struct APIItineraryRepository: ItineraryRepository {
    private typealias CreateRequest = Components.Schemas.CreateItineraryRequestDto
    private typealias UpdateRequest = Components.Schemas.UpdateItineraryRequestDto
    private typealias DetailResponse = Components.Schemas.ItineraryDto_Output
    private typealias ListResponse = Components.Schemas.ListItinerariesResponseDto_Output
    private typealias RenameRequest = Components.Schemas.RenameItineraryRequestDto

    let apiClient: APIClient
    /// The API's maximum: a full resync reads every page.
    var pageSize = 50

    private struct ErrorEnvelope: Decodable {
        struct Body: Decodable { let code: String }
        let error: Body
    }

    func create(_ creation: ItineraryCreation) async throws(ItineraryError) -> CreatedItinerary {
        let body = CreateRequest(
            waypoints: creation.waypoints.map { .init(lat: $0.latitude, lon: $0.longitude) },
            legs: creation.legs.map { leg in
                switch leg {
                case .follow(let path): .case1(.init(mode: .follow, polyline6: path.value))
                case .straight: .case2(.init(mode: .straight))
                }
            },
            name: creation.name,
            sportTypeCode: creation.sport.rawValue,
            id: creation.id.description
        )
        let (response, http): (DetailResponse, HTTPURLResponse) = try await call { () async throws(APIError) in
            try await apiClient.sendWithHeaders(method: "POST", path: "/v1/itineraries", body: body)
        }
        guard let detail = response.model else { throw .server(code: nil) }
        return CreatedItinerary(detail: detail, isReplay: http.statusCode == 200)
    }

    func update(_ edit: ItineraryCreation) async throws(ItineraryError) -> ItineraryDetail {
        let body = UpdateRequest(
            waypoints: edit.waypoints.map { .init(lat: $0.latitude, lon: $0.longitude) },
            legs: edit.legs.map { leg in
                switch leg {
                case .follow(let path): .case1(.init(mode: .follow, polyline6: path.value))
                case .straight: .case2(.init(mode: .straight))
                }
            },
            name: edit.name,
            sportTypeCode: edit.sport.rawValue
        )
        let response: DetailResponse = try await call { () async throws(APIError) in
            try await apiClient.send(method: "PUT", path: "/v1/itineraries/\(edit.id)", body: body)
        }
        guard let detail = response.model else { throw .server(code: nil) }
        return detail
    }

    func savedItinerary(id: ItineraryID) async throws(ItineraryError) -> SavedItinerary {
        let response: DetailResponse = try await call { () async throws(APIError) in
            try await apiClient.get("/v1/itineraries/\(id)")
        }
        guard let saved = response.savedItinerary else { throw .server(code: nil) }
        return saved
    }

    func page(cursor: String?) async throws(ItineraryError) -> ItineraryPage {
        var query = [URLQueryItem(name: "limit", value: String(pageSize))]
        if let cursor {
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }
        let response: ListResponse = try await call { () async throws(APIError) in
            try await apiClient.get("/v1/itineraries", query: query)
        }
        return ItineraryPage(items: response.items.compactMap(\.model), nextCursor: response.nextCursor)
    }

    func detail(id: ItineraryID) async throws(ItineraryError) -> ItineraryDetail {
        let response: DetailResponse = try await call { () async throws(APIError) in
            try await apiClient.get("/v1/itineraries/\(id)")
        }
        guard let detail = response.model else { throw .server(code: nil) }
        return detail
    }

    func rename(id: ItineraryID, to name: String) async throws(ItineraryError) -> ItineraryDetail {
        let response: DetailResponse = try await call(rejectingClientErrors: true) { () async throws(APIError) in
            try await apiClient.send(method: "PATCH", path: "/v1/itineraries/\(id)", body: RenameRequest(name: name))
        }
        guard let detail = response.model else { throw .server(code: nil) }
        return detail
    }

    func delete(id: ItineraryID) async throws(ItineraryError) {
        let _: NoContent = try await call(rejectingClientErrors: true) { () async throws(APIError) in
            try await apiClient.send(method: "DELETE", path: "/v1/itineraries/\(id)")
        }
    }

    /// `rejectingClientErrors`: any `4xx` without a case of its own is `invalid`, never worth
    /// retrying (the queued changes, ADR-030 §8).
    private func call<T>(
        rejectingClientErrors: Bool = false,
        _ operation: () async throws(APIError) -> T
    ) async throws(ItineraryError) -> T {
        do {
            return try await operation()
        } catch {
            switch error {
            case .offline: throw .offline
            case .unauthorized: throw .unauthorized
            case .http(404, _): throw .notFound
            case .http(409, _): throw .conflict
            case .http(503, _): throw .unavailable
            case .http(let status, let body):
                let code = body.flatMap { try? JSONDecoder().decode(ErrorEnvelope.self, from: $0) }?.error.code
                let isRejected = status == 422 || (rejectingClientErrors && (400 ..< 500).contains(status))
                throw isRejected ? .invalid(code: code) : .server(code: code)
            case .decoding: throw .server(code: nil)
            case .transport: throw .network
            }
        }
    }
}

private extension Components.Schemas.ItineraryDto_Output {
    var model: ItineraryDetail? {
        guard let id = ItineraryID(id), let source = ElevationSource(rawValue: elevationSource.rawValue) else {
            return nil
        }
        return ItineraryDetail(
            id: id,
            name: name,
            sport: SportType(code: sportTypeCode),
            distance: Distance(meters: distanceM),
            elevationGain: elevationGainM,
            elevationSource: source,
            track: ItineraryTrack(polyline: EncodedPolyline(value: track.polyline6, precision: 6), altitudes: track.altitudesM),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    /// The Waypoints and Legs as stored. A `straight` Leg comes with the line the API drew,
    /// which the editor draws itself.
    var savedItinerary: SavedItinerary? {
        guard let id = ItineraryID(id), let sport = ItinerarySport(rawValue: sportTypeCode) else { return nil }
        return SavedItinerary(
            id: id,
            name: name,
            sport: sport,
            waypoints: waypoints.map { Coordinate(latitude: $0.lat, longitude: $0.lon) },
            legs: legs.map { leg in
                switch leg.mode {
                case .follow: .follow(EncodedPolyline(value: leg.polyline6, precision: 6))
                case .straight: .straight
                }
            }
        )
    }
}

private extension Components.Schemas.ListItinerariesResponseDto_Output.itemsPayloadPayload {
    var model: ItinerarySummary? {
        guard let id = ItineraryID(id) else { return nil }
        return ItinerarySummary(
            id: id,
            name: name,
            sport: SportType(code: sportTypeCode),
            distance: Distance(meters: distanceM),
            elevationGain: elevationGainM,
            mapPolyline: EncodedPolyline(value: mapPolyline),
            updatedAt: updatedAt
        )
    }
}
