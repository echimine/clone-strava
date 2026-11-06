import Foundation

/// `APIClient` adapter of `SegmentMapRepository` (ADR-039 §12), on the types generated from
/// openapi.json (ADR-026 §5).
struct APISegmentMapRepository: SegmentMapRepository {
    private typealias Response = Components.Schemas.ListMapSegmentsResponseDto_Output

    let apiClient: APIClient

    func segments(in area: MapArea, filter: SegmentMapFilter) async throws(SegmentError) -> [MapSegment] {
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
        let response: Response = try await SegmentAPIError.call { () async throws(APIError) in
            try await apiClient.get("/v1/segments", query: query)
        }
        return response.items.compactMap(\.model)
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
            isFavorite: starred,
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
