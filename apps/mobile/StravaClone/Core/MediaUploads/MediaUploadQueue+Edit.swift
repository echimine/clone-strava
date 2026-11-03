import Foundation

/// What "Enregistrer" in "Modifier" asks of the queue (ADR-037 §8, §10, #184): a new order for
/// the Media still being sent, and the deletion of a confirmed one.
extension MediaUploadQueue {
    /// Each row of `activityID` listed in `order` takes its index there: the `position` it
    /// confirms with, so it lands at its place without a second `PATCH`.
    func reorder(_ order: [UUID], of activityID: ActivityID) async {
        let positions = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        try? await store.reposition(positions)
        board.reorder(positions, of: activityID)
        await refreshBoard()
    }

    /// "Supprimer" on a confirmed Media: forgotten at once by the board (else it would show
    /// again from the Media confirmed during this launch), then `DELETE`d. False when the
    /// `DELETE` did not go through: the server's copy still has it.
    func deleteConfirmed(_ mediaID: UUID, of activityID: ActivityID) async -> Bool {
        board.forget(mediaID)
        let result = await attempt { () async throws(MediaServerError) in
            try await self.server.delete(mediaID, of: activityID)
        }
        switch result {
        case .success, .failure(.notFound): return true
        case .failure: return false
        }
    }
}
