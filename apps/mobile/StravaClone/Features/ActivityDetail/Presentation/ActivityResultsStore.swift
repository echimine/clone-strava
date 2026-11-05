import Foundation
import Observation

/// « Résultats » of an open Activity (spec #252): loaded and reloaded with its detail, so that
/// `activity.segments_matched` (read as an update, ADR-039 §14) fills in the Segments. A failed
/// load keeps what is shown; without anything loaded, the section is simply absent.
@Observable
@MainActor
final class ActivityResultsStore {
    let id: ActivityID
    private(set) var results: ActivityResults?
    /// The Best effort whose removal waits for its confirmation.
    var removalCandidate: BestEffortResult?
    /// Short-lived message over the detail: a removal done or failed.
    var notice: String?

    @ObservationIgnored private let loadResults: LoadActivityResults
    @ObservationIgnored private let removeBestEffort: RemoveBestEffort
    @ObservationIgnored private let analytics: any AnalyticsClient
    /// After a removal: the detail reloads, the card's « Performances » changed too.
    @ObservationIgnored var onRemoved: @MainActor () async -> Void

    init(
        id: ActivityID,
        loadResults: LoadActivityResults,
        removeBestEffort: RemoveBestEffort,
        analytics: any AnalyticsClient = NoAnalyticsClient(),
        onRemoved: @escaping @MainActor () async -> Void = {}
    ) {
        self.id = id
        self.loadResults = loadResults
        self.removeBestEffort = removeBestEffort
        self.analytics = analytics
        self.onRemoved = onRemoved
    }

    func load() async {
        if let results = try? await loadResults(id) {
            self.results = results
        }
    }

    /// « Retirer ce temps de mes meilleurs efforts », once confirmed: for good (ADR-039 §3).
    func remove(_ effort: BestEffortResult) async {
        guard effort.removable else { return }
        do {
            try await removeBestEffort(effort.distanceM, of: id)
        } catch {
            notice = ActivityDetailMessages.message(for: error)
            return
        }
        analytics.capture(.bestEffortRemoved(distanceM: effort.distanceM))
        notice = ActivityResultsMessages.removed
        await load()
        await onRemoved()
    }

    /// The Best effort a line of « Résultats » stands for, to remove it.
    func bestEffort(for line: ActivityResultLine) -> BestEffortResult? {
        guard case .bestEffort(let distanceM) = line.target else { return nil }
        return results?.bestEfforts.first { $0.distanceM == distanceM }
    }
}
