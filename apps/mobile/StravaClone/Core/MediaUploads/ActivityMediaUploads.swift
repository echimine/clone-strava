import Foundation

/// What a screen needs to manage an Activity's Media (ADR-037 §5, §8, §10): the board of the
/// Media being sent, and the queue's operations. Handed by the app shell to the edit sheet and
/// to the finish screen, so no feature imports another.
struct ActivityMediaUploads {
    let board: MediaUploadBoard
    let enqueue: @MainActor (_ picked: [(media: PickedMedia, position: Int)], _ activityID: ActivityID) async -> Void
    /// Media still being sent, removed: tasks cancelled, rows and local files deleted.
    var discard: @MainActor (_ mediaIDs: [UUID]) async -> Void = { _ in }
    /// The rows of the Activity take their index in the full order as their `position`.
    var reorder: @MainActor (_ order: [UUID], _ activityID: ActivityID) async -> Void = { _, _ in }
    /// `DELETE` of a confirmed Media, forgotten by the board; false when it did not go through.
    var delete: @MainActor (_ mediaID: UUID, _ activityID: ActivityID) async -> Bool = { _, _ in true }
    /// Where `activity_media_saved` goes.
    var analytics: any AnalyticsClient = NoAnalyticsClient()

    // MARK: - Finish screen (ADR-037 §6)

    /// Picked on the finish screen: exported at once, before Save.
    var prepare: @MainActor (_ picked: [PickedMedia]) -> Void = { _ in }
    /// Gone from the finish screen's strip, or the Recording deleted: export stopped, files deleted.
    var release: @MainActor (_ mediaIDs: [UUID]) -> Void = { _ in }
    /// The `media_upload` rows Save writes in its transaction.
    var uploads: @MainActor (_ picked: [(media: PickedMedia, position: Int)], _ activityID: ActivityID) -> [MediaUpload] = { _, _ in [] }
    /// After Save's commit: the queue takes the rows over.
    var adopt: @MainActor (_ picked: [PickedMedia]) async -> Void = { _ in }
}

extension ActivityMediaUploads {
    /// Every operation over the app's queue.
    @MainActor
    init(queue: MediaUploadQueue, analytics: any AnalyticsClient) {
        self.init(
            board: queue.board,
            enqueue: { picked, activityID in await queue.enqueue(picked, to: activityID) },
            discard: { mediaIDs in await queue.discard(mediaIDs) },
            reorder: { order, activityID in await queue.reorder(order, of: activityID) },
            delete: { mediaID, activityID in await queue.deleteConfirmed(mediaID, of: activityID) },
            analytics: analytics,
            prepare: { picked in queue.prepare(picked) },
            release: { mediaIDs in queue.release(mediaIDs) },
            uploads: { picked, activityID in queue.uploads(for: picked, to: activityID) },
            adopt: { picked in await queue.adopt(picked) }
        )
    }

    /// "Enregistrer" with `draft` (#184), before the single `PATCH` (`mediaOrder`, `mediaFirst`):
    /// `activity_media_saved` is sent (nothing for an unchanged draft); a Media removed while
    /// still being sent is discarded, a confirmed one `DELETE`d; the rows being sent take their
    /// new index and the picked Media are queued at theirs. Returns false when a `DELETE` did
    /// not go through.
    @MainActor
    func save(_ draft: MediaDraft, to activityID: ActivityID, entry: AnalyticsEvent.ActivityMediaSavedEntry) async -> Bool {
        guard draft.hasChanges else { return true }
        let sending = board.pendingIDs(of: activityID)
        let removed = draft.removed.map(\.id)
        let confirmed = removed.filter { !sending.contains($0) }
        await discard(removed.filter(sending.contains))
        for mediaID in confirmed {
            board.forget(mediaID)
        }
        await reorder(draft.order, activityID)
        await enqueue(draft.queued, activityID)
        // After the queue has its rows: counting the cut videos may wait for a library copy.
        if let saved = await draft.saved() {
            analytics.capture(.activityMediaSaved(entry: entry, saved))
        }
        var deleted = true
        for mediaID in confirmed {
            if await !delete(mediaID, activityID) { deleted = false }
        }
        return deleted
    }
}
