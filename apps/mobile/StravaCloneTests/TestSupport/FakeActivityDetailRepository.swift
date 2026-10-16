import Foundation
@testable import StravaClone

/// In-memory `ActivityDetailRepository`: answers scripted in order (the last one repeats),
/// recorded calls.
final class FakeActivityDetailRepository: ActivityDetailRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<ActivityDetail, ActivityDetailError>]
    private(set) var requestedIds: [ActivityID] = []

    init(_ results: Result<ActivityDetail, ActivityDetailError>...) {
        self.results = results
    }

    func detail(id: ActivityID) async throws(ActivityDetailError) -> ActivityDetail {
        let result = lock.withLock {
            requestedIds.append(id)
            return results.count > 1 ? results.removeFirst() : results.first ?? .failure(.network)
        }
        return try result.get()
    }
}

extension ActivityDetail {
    static func fixture(
        id: ActivityID = ActivityID(),
        title: String = "Sortie du matin",
        description: String? = nil,
        sport: SportType = .run,
        stats: ActivityStats? = .fixture(),
        route: EncodedPolyline? = EncodedPolyline(value: "_p~iF~ps|U_ulLnnqC_mqNvxq`@"),
        engagement: ActivityEngagement = ActivityEngagement(kudosCount: 2, commentCount: 1, viewerHasKudoed: false),
        viewerIsAuthor: Bool = true
    ) -> ActivityDetail {
        ActivityDetail(
            id: id,
            title: title,
            description: description,
            sport: sport,
            visibility: .public,
            startedAt: Date(timeIntervalSince1970: 1_790_000_000),
            locationName: "Annecy, Haute-Savoie",
            stats: stats,
            route: route,
            author: ActivityAuthor(id: "u1", displayName: "Camille Martin", avatarURL: nil),
            engagement: engagement,
            viewerIsAuthor: viewerIsAuthor
        )
    }
}

extension ActivityStats {
    static func fixture(
        distanceM: Double? = 10_000,
        movingTimeS: Int? = 3_000,
        elapsedTimeS: Int? = 3_200,
        elevationGainM: Double? = 120,
        avgSpeedMs: Double? = 10_000.0 / 3_000.0,
        maxSpeedMs: Double? = 5,
        avgHeartRate: Int? = nil,
        maxHeartRate: Int? = nil,
        calories: Int? = nil
    ) -> ActivityStats {
        ActivityStats(
            distance: distanceM.map { Distance(meters: $0) },
            movingTime: movingTimeS.map { .seconds($0) },
            elapsedTime: elapsedTimeS.map { .seconds($0) },
            elevationGain: elevationGainM,
            avgSpeedMs: avgSpeedMs,
            maxSpeedMs: maxSpeedMs,
            avgHeartRate: avgHeartRate,
            maxHeartRate: maxHeartRate,
            calories: calories
        )
    }
}
