import Foundation
import Observation

/// Réglages > "Athlètes bloqués" (ADR-038 §8): those the viewer blocked, each with a confirmed
/// "Débloquer". Online only.
@MainActor
@Observable
final class BlockedAthletesStore {
    enum Phase: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    private(set) var phase = Phase.idle
    private(set) var athletes: [BlockedAthlete] = []
    /// "Débloquer <prénom> ?", waiting for its confirmation.
    var unblockCandidate: BlockedAthlete?
    var toast: String?

    @ObservationIgnored private let loadBlockedAthletes: LoadBlockedAthletes
    @ObservationIgnored private let unblockAthlete: UnblockAthlete
    @ObservationIgnored private let analytics: any AnalyticsClient

    init(
        loadBlockedAthletes: LoadBlockedAthletes,
        unblockAthlete: UnblockAthlete,
        analytics: any AnalyticsClient = NoAnalyticsClient()
    ) {
        self.loadBlockedAthletes = loadBlockedAthletes
        self.unblockAthlete = unblockAthlete
        self.analytics = analytics
    }

    func load() async {
        if athletes.isEmpty { phase = .loading }
        do {
            athletes = try await loadBlockedAthletes()
            phase = .loaded
        } catch {
            if athletes.isEmpty {
                phase = .failed(ModerationMessages.message(for: error))
            } else {
                toast = ModerationMessages.message(for: error)
            }
        }
    }

    /// The confirmation's "Débloquer": the athlete leaves the list once the server agreed.
    func confirmUnblock() async {
        guard let candidate = unblockCandidate else { return }
        unblockCandidate = nil
        do {
            try await unblockAthlete(candidate.athlete.id)
            analytics.capture(.athleteUnblocked)
            athletes.removeAll { $0.id == candidate.id }
        } catch {
            toast = ModerationMessages.message(for: error)
        }
    }
}
