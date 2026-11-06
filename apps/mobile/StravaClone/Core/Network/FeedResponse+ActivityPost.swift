import Foundation

/// The cards of `GET /v1/feed` and of `GET /v1/athletes/:id/activities`, which share one
/// response format (ADR-029 §1, ADR-036 §3), decoded with the generated OpenAPI types (ADR-026).
extension Components.Schemas.FeedResponseDto_Output {
    var page: FeedPage {
        FeedPage(posts: items.compactMap(\.model), nextCursor: nextCursor)
    }
}

private extension Components.Schemas.FeedResponseDto_Output.itemsPayloadPayload {
    /// Nil for an item whose id is not a UUID, which the API never sends.
    var model: ActivityPost? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return ActivityPost(
            id: ActivityID(uuid),
            title: title,
            sport: SportType(code: sportTypeCode),
            startedAt: startedAt,
            locationName: locationName,
            distance: stats.distanceM.map { Distance(meters: $0) },
            movingTime: stats.movingTimeS.map { .seconds($0) },
            elevationGain: stats.elevationGainM,
            avgSpeedMs: stats.avgSpeedMs,
            route: map.map { EncodedPolyline(value: $0.polyline, precision: Int($0.precision)) },
            routeTrimmed: routeTrimmed,
            author: ActivityAuthor(id: author.id, displayName: author.displayName, avatarUrl: author.avatarUrl),
            engagement: ActivityEngagement(
                kudosCount: engagement.kudosCount,
                commentCount: engagement.commentCount,
                viewerHasKudoed: engagement.viewerHasKudoed
            ),
            recentKudos: recentKudos.map {
                ActivityAuthor(id: $0.id, displayName: $0.displayName, avatarUrl: $0.avatarUrl)
            },
            viewerIsAuthor: viewerIsAuthor,
            media: media.models,
            mediaFirst: mediaFirst,
            medalCounts: MedalCounts(gold: medalCounts.gold, silver: medalCounts.silver, bronze: medalCounts.bronze)
        )
    }
}
