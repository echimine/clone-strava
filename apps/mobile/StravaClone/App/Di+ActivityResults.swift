import Foundation

/// « Résultats » of an Activity's detail (spec #252): its Best efforts and Efforts on Segments.
extension Di {
    /// Owned by the detail's store, one per opened Activity.
    func makeActivityResultsStore(id: ActivityID) -> ActivityResultsStore {
        let repository = APIActivityResultsRepository(apiClient: apiClient)
        return ActivityResultsStore(
            id: id,
            loadResults: LoadActivityResults(repository: repository),
            removeBestEffort: RemoveBestEffort(repository: repository),
            analytics: analytics
        )
    }
}
