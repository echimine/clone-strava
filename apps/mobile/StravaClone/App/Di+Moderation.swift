import Foundation

/// Reports and Blocks (ADR-038 §8, §9): the sheet and confirmations over the tabs, and
/// Réglages > "Athlètes bloqués".
extension Di {
    /// One for the whole signed-in app: installed over the tabs by the app shell.
    func makeModerationStore() -> ModerationStore {
        let repository = APIModerationRepository(apiClient: apiClient)
        return ModerationStore(
            reportContent: ReportContent(repository: repository),
            blockAthlete: BlockAthlete(repository: repository),
            changes: activityChanges,
            analytics: analytics
        )
    }

    /// A new one each time Réglages pushes the list.
    func makeBlockedAthletesStore() -> BlockedAthletesStore {
        let repository = APIModerationRepository(apiClient: apiClient)
        return BlockedAthletesStore(
            loadBlockedAthletes: LoadBlockedAthletes(repository: repository),
            unblockAthlete: UnblockAthlete(repository: repository),
            analytics: analytics
        )
    }
}
