import Foundation

/// `APIClient` adapter of `AthleteGalleryRepository`: `GET /v1/athletes/:id/media` (ADR-037 §9),
/// decoded with the generated OpenAPI types (ADR-026).
struct APIAthleteGalleryRepository: AthleteGalleryRepository {
    private typealias Response = Components.Schemas.GalleryResponseDto_Output

    let apiClient: APIClient
    /// The API's default: ten rows of three.
    var pageSize = 30

    func gallery(of athleteId: String, cursor: String?) async throws(AthleteError) -> GalleryPage {
        var query = [URLQueryItem(name: "limit", value: String(pageSize))]
        if let cursor {
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }
        let response: Response = try await APIAthleteErrors.call { () async throws(APIError) in
            try await apiClient.get("/v1/athletes/\(athleteId)/media", query: query)
        }
        return GalleryPage(items: response.items.compactMap(\.model), nextCursor: response.nextCursor)
    }
}

private extension Components.Schemas.GalleryItem_Output {
    /// Nil for an item whose ids or URLs do not parse, which the API never sends.
    var model: GalleryItem? {
        guard let activityUUID = UUID(uuidString: activity.id), let media = mediaModel else { return nil }
        return GalleryItem(
            media: media,
            activity: GalleryActivity(id: ActivityID(activityUUID), title: activity.title, startedAt: activity.startedAt)
        )
    }

    /// The Media fields, the same as `Media_Output` (ADR-037 §7).
    private var mediaModel: ActivityMedia? {
        Components.Schemas.Media_Output(
            id: id,
            kind: kind == .video ? .video : .photo,
            width: width,
            height: height,
            durationMs: durationMs,
            url: url,
            posterUrl: posterUrl,
            thumbUrl: thumbUrl
        ).model
    }
}
