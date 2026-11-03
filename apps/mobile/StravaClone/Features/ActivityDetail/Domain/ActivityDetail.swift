import Foundation

/// Official values of a processed Activity (`activity_stats`, ADR-033 §2). Each one is nil
/// when it was not measured.
struct ActivityStats: Hashable, Sendable {
    let distance: Distance?
    let movingTime: Duration?
    let elapsedTime: Duration?
    let elevationGain: Double?
    let avgSpeedMs: Double?
    let maxSpeedMs: Double?
    let avgHeartRate: Int?
    let maxHeartRate: Int?
    let calories: Int?
}

/// An Activity as the detail screen shows it (`GET /v1/activities/:id`, ADR-033 §2, §3).
struct ActivityDetail: Hashable, Sendable {
    let id: ActivityID
    var title: String
    /// Nil when empty.
    var description: String?
    var sport: SportType
    var visibility: ActivityVisibility
    let startedAt: Date
    let locationName: String?
    let source: ActivitySource
    /// Nil until processed.
    var stats: ActivityStats?
    /// The privacy-zoned polyline (ADR-029 §3); nil without GPS.
    let route: EncodedPolyline?
    /// True when the privacy zone removed part of the route (ADR-036 §5).
    let routeTrimmed: Bool
    /// Splits and series (ADR-036 §6); nil while not computed yet.
    let analysis: ActivityAnalysis?
    let author: ActivityAuthor
    var engagement: ActivityEngagement
    let viewerIsAuthor: Bool

    /// The feed card of this Activity, as the change stream hands it to the feed (ADR-033 §7).
    var post: ActivityPost {
        ActivityPost(
            id: id,
            title: title,
            sport: sport,
            startedAt: startedAt,
            locationName: locationName,
            distance: stats?.distance,
            movingTime: stats?.movingTime,
            elevationGain: stats?.elevationGain,
            route: route,
            author: author,
            engagement: engagement,
            viewerIsAuthor: viewerIsAuthor
        )
    }
}
