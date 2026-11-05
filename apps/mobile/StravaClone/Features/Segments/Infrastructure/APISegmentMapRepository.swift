import Foundation

/// `APIClient` adapter of `SegmentMapRepository` (ADR-039 §12), on the types generated from
/// openapi.json (ADR-026 §5).
struct APISegmentMapRepository: SegmentMapRepository {
    private typealias Response = Components.Schemas.ListMapSegmentsResponseDto_Output

    let apiClient: APIClient

    private struct ErrorEnvelope: Decodable {
        struct Body: Decodable { let code: String }
        let error: Body
    }

    func segments(in area: MapArea, filter: SegmentMapFilter) async throws(SegmentMapError) -> [MapSegment] {
        let bbox = [area.southWest.longitude, area.southWest.latitude, area.northEast.longitude, area.northEast.latitude]
            .map { String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), $0) }
            .joined(separator: ",")
        var query = [URLQueryItem(name: "bbox", value: bbox)]
        if let sport = filter.sport {
            query.append(URLQueryItem(name: "sport", value: sport.rawValue))
        }
        if filter.favoritesOnly {
            query.append(URLQueryItem(name: "favorites", value: "true"))
        }
        do {
            let response: Response = try await apiClient.get("/v1/segments", query: query)
            return response.items.compactMap(\.model)
        } catch {
            switch error {
            case .offline: throw .offline
            case .http(400, let body):
                let code = body.flatMap { try? JSONDecoder().decode(ErrorEnvelope.self, from: $0) }?.error.code
                throw code == "zone_too_large" ? .zoneTooLarge : .failed
            default: throw .failed
            }
        }
    }
}

private extension Components.Schemas.ListMapSegmentsResponseDto_Output.itemsPayloadPayload {
    var model: MapSegment? {
        guard let sport = SegmentSport(rawValue: sportTypeCode.rawValue) else { return nil }
        return MapSegment(
            id: id,
            sport: sport,
            name: name,
            isVerified: verified,
            isStarred: starred,
            distance: Distance(meters: distanceM),
            averageGradePct: averageGradePct,
            climbCategory: climbCategory.flatMap { ClimbCategory(rawValue: $0.rawValue) },
            athleteCount: athleteCount,
            myBestTime: myBestTimeS.map { .seconds($0) },
            leaderTime: leaderTimeS.map { .seconds($0) },
            path: EncodedPolyline(value: mapPolyline).decode()
        )
    }
}
