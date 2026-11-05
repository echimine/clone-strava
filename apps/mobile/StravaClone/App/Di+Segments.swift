import Foundation

/// A Segment's sheet and Leaderboard (ADR-039 §15), and the Paywall their locks open in a sheet.
extension Di {
    func makeSegmentScreens() -> SegmentScreens {
        let repository = APISegmentRepository(apiClient: apiClient)
        return SegmentScreens(
            makeSheetStore: { id, onDeleted in
                SegmentSheetStore(segmentID: id, repository: repository, onDeleted: onDeleted)
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
