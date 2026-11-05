import Foundation

/// Segments (ADR-039 §15): the Map tab's Segments mode, a Segment's sheet and Leaderboard, and
/// the Paywall their locks open in a sheet.
extension Di {
    /// One for the Map tab, kept across mode switches.
    func makeSegmentMapStore() -> SegmentMapStore {
        SegmentMapStore(
            repository: APISegmentMapRepository(apiClient: apiClient),
            favorites: APISegmentFavoriteRepository(apiClient: apiClient),
            analytics: analytics
        )
    }

    func makeSegmentScreens() -> SegmentScreens {
        let repository = APISegmentRepository(apiClient: apiClient)
        return SegmentScreens(
            makeSheetStore: { [analytics] id, onDeleted in
                SegmentSheetStore(segmentID: id, repository: repository, analytics: analytics, onDeleted: onDeleted)
            },
            makeLeaderboardStore: { [analytics] id in
                LeaderboardStore(segmentID: id, repository: repository, analytics: analytics)
            },
            makePaywallStore: { [subscriptionService, analytics] entry, finish in
                // No notification primer on this path: `finish` only closes the sheet (ADR-039 §9).
                PaywallStore(service: subscriptionService, analytics: analytics, entry: entry, finish: finish)
            }
        )
    }
}

/// What the shell needs to build a Segment's sheet in any stack (ADR-007 rule 5).
struct SegmentScreens {
    let makeSheetStore: @MainActor (String, @escaping @MainActor () -> Void) -> SegmentSheetStore
    let makeLeaderboardStore: @MainActor (String) -> LeaderboardStore
    let makePaywallStore: @MainActor (AnalyticsEvent.PaywallEntry, @escaping @MainActor () -> Void) -> PaywallStore
}
