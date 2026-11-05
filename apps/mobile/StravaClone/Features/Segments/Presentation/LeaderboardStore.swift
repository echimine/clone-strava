import Foundation
import Observation

/// A Segment's Leaderboard screen (ADR-039 §8, §9, §15). It opens on Tous; without Premium (the
/// server answers `limited`), every other chip and the insert open the Paywall in a sheet, as
/// many times as tapped. With Premium, pages of 50 follow the end of the list.
@MainActor
@Observable
final class LeaderboardStore {
    /// The Paywall in a sheet; a new id on each tap, so it opens again every time.
    struct PaywallRequest: Identifiable, Equatable {
        let id = UUID()
        let entry: AnalyticsEvent.PaywallEntry
    }

    private(set) var selection = LeaderboardSelection()
    private(set) var leaderboard: Leaderboard?
    private(set) var isLoading = false
    var paywall: PaywallRequest?
    var toast: String?

    @ObservationIgnored private let segmentID: String
    @ObservationIgnored private let repository: any SegmentRepository
    @ObservationIgnored private let analytics: any AnalyticsClient
    @ObservationIgnored private var isLoadingMore = false

    init(segmentID: String, repository: any SegmentRepository, analytics: any AnalyticsClient = NoAnalyticsClient()) {
        self.segmentID = segmentID
        self.repository = repository
        self.analytics = analytics
    }

    /// Locks follow the server: until it answers, everything but Tous is locked.
    private var isPremium: Bool { leaderboard.map { !$0.limited } ?? false }

    func isLocked(_ gender: LeaderboardGender) -> Bool { !isPremium && gender != .all }
    func isLocked(_ filter: LeaderboardFilter) -> Bool { !isPremium }

    func appeared() async {
        guard leaderboard == nil else { return }
        await show(selection)
    }

    /// Pull-to-refresh, and after the Paywall closes (Premium may have started).
    func reload() async {
        await load(selection)
    }

    /// A chip: a locked one opens the Paywall at once, any other loads its Leaderboard.
    func tap(_ gender: LeaderboardGender) {
        if isLocked(gender) { return openPaywall(.leaderboardFilter) }
        Task { await select(gender) }
    }

    func tap(_ filter: LeaderboardFilter) {
        if isLocked(filter) { return openPaywall(.leaderboardFilter) }
        Task { await select(filter) }
    }

    func select(_ gender: LeaderboardGender) async {
        if isLocked(gender) { return openPaywall(.leaderboardFilter) }
        await show(selection.tapping(gender))
    }

    func select(_ filter: LeaderboardFilter) async {
        if isLocked(filter) { return openPaywall(.leaderboardFilter) }
        await show(selection.tapping(filter))
    }

    /// « Voir le classement complet avec Premium ».
    func tapPremiumInsert() {
        openPaywall(.segmentLeaderboard)
    }

    func paywallClosed() {
        paywall = nil
    }

    /// The next page of 50, once the end of the list shows.
    func loadMore() async {
        guard let current = leaderboard, let cursor = current.nextCursor, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await repository.leaderboard(id: segmentID, selection: selection, cursor: cursor)
            guard leaderboard?.nextCursor == cursor else { return }
            leaderboard?.entries += page.entries
            leaderboard?.nextCursor = page.nextCursor
        } catch {
            toast = SegmentMessages.message(for: error)
        }
    }

    private func show(_ next: LeaderboardSelection) async {
        if await load(next) {
            analytics.capture(.leaderboardViewed(filter: next.analytics))
        }
    }

    @discardableResult
    private func load(_ next: LeaderboardSelection) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await repository.leaderboard(id: segmentID, selection: next, cursor: nil)
            selection = next
            leaderboard = loaded
            return true
        } catch .premiumRequired {
            // Premium ended meanwhile: back to Tous, and the Paywall.
            if let tous = try? await repository.leaderboard(id: segmentID, selection: LeaderboardSelection(), cursor: nil) {
                leaderboard = tous
            }
            selection = LeaderboardSelection()
            openPaywall(.leaderboardFilter)
            return false
        } catch {
            toast = SegmentMessages.message(for: error)
            return false
        }
    }

    private func openPaywall(_ entry: AnalyticsEvent.PaywallEntry) {
        paywall = PaywallRequest(entry: entry)
    }
}
