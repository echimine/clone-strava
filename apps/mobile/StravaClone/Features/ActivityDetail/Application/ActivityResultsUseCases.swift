import Foundation

/// Loads « Résultats » of an Activity (ADR-039 §12).
struct LoadActivityResults: Sendable {
    let repository: any ActivityResultsRepository

    func callAsFunction(_ id: ActivityID) async throws(ActivityDetailError) -> ActivityResults {
        try await repository.results(of: id)
    }
}

/// « Retirer ce temps de mes meilleurs efforts » (ADR-039 §3): for good.
struct RemoveBestEffort: Sendable {
    let repository: any ActivityResultsRepository

    func callAsFunction(_ distanceM: Double, of id: ActivityID) async throws(ActivityDetailError) {
        try await repository.removeBestEffort(of: id, distanceM: distanceM)
    }
}
