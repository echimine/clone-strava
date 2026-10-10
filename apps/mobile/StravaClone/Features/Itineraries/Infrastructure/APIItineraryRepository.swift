import Foundation

/// `APIClient` adapter of `ItineraryRepository` (ADR-030 §6), on the types generated from
/// openapi.json (ADR-026 §5).
struct APIItineraryRepository: ItineraryRepository {
    private typealias CreateRequest = Components.Schemas.CreateItineraryRequestDto
    private typealias DetailResponse = Components.Schemas.ItineraryDto_Output
    private typealias ListResponse = Components.Schemas.ListItinerariesResponseDto_Output

    let apiClient: APIClient
    /// The API's maximum: a full resync reads every page.
    var pageSize = 50

    private struct ErrorEnvelope: Decodable {
        struct Body: Decodable { let code: String }
        let error: Body
    }

    func create(_ creation: ItineraryCreation) async throws(ItineraryError) -> ItineraryDetail {
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
        let response: DetailResponse = try await call { () async throws(APIError) in
            try await apiClient.send(method: "POST", path: "/v1/itineraries", body: body)
        }
        guard let detail = response.model else { throw .server(code: nil) }
        return detail
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

    private func call<T>(_ operation: () async throws(APIError) -> T) async throws(ItineraryError) -> T {
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
                throw status == 422 ? .invalid(code: code) : .server(code: code)
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
