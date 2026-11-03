import Foundation

/// The Media follow their Activity's Delete (ADR-037 §6): wiped at once with an Activity the
/// server never had; held while `delete_activity` waits, then dropped at `204`/`404` or sent
/// again at `409`. Holding them back is `canSend`'s job (no Delete pending); here the running
/// `PUT`s stop, their rows and files kept.
extension MediaUploadQueue {
    /// `delete_activity` is queued: the Activity's running `PUT`s are cancelled, and nothing
    /// more goes until the server answers.
    func hold(mediaOf activityID: ActivityID) async {
        let ids = (try? await store.mediaIDs(of: activityID)) ?? []
        guard !ids.isEmpty else { return }
        await cancelTasks(of: ids)
        await refreshBoard()
    }

    /// The Activity is gone: its rows, files and tasks go, silently.
    func discard(mediaOf activityID: ActivityID) async {
        let ids = (try? await store.mediaIDs(of: activityID)) ?? []
        guard !ids.isEmpty else { return }
        await discard(ids)
    }

    /// For the sign-out confirmation: the Media not yet confirmed, `failed` included, but those
    /// of `excluded` (Activities whose Delete waits for the server, already given up).
    func unsentCount(excluding excluded: Set<ActivityID>) async -> Int {
        (try? await store.count(excluding: excluded)) ?? 0
    }
}
