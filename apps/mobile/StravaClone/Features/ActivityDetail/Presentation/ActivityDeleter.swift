import Foundation
import Observation

/// "Supprimer", once confirmed, from the detail's "⋯" or a feed card's context menu
/// (ADR-033 §7). Online and optimistic: the card goes at once, then the request is sent; a
/// failure brings the card back with a toast. One instance, shown over the feed: from the
/// detail, the athlete is back on the feed by the time the server answers.
@Observable
@MainActor
final class ActivityDeleter {
    /// A deletion that failed.
    var toast: String?

    @ObservationIgnored private let deleteActivity: DeleteActivity
    @ObservationIgnored private let changes: ActivityChanges

    /// - Parameter changes: where the deletion, and its undoing on failure, is published for
    ///   the feed's card.
    init(deleteActivity: DeleteActivity, changes: ActivityChanges) {
        self.deleteActivity = deleteActivity
        self.changes = changes
    }

    func delete(_ id: ActivityID) async {
        changes.publish(.deleted(id))
        do {
            try await deleteActivity(id)
        } catch {
            changes.publish(.restored(id))
            toast = ActivityDetailMessages.deleteFailed(error)
        }
    }
}
