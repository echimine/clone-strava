import Foundation

/// The Media of an Activity (ADR-037 §5): the queue of `media_upload`, its background session
/// and what the screens get of it.
extension Di {
    /// The queue over the app's background session, its files in Application Support. The
    /// session must exist at launch: iOS hands it the events of uploads finished meanwhile.
    static func makeMediaUploadQueue(
        database: AppDatabase,
        apiClient: APIClient,
        authSession: AuthSession,
        analytics: any AnalyticsClient,
        imageLoader: ImageLoader,
        transfer: BackgroundMediaTransfer
    ) -> MediaUploadQueue {
        let files = (try? MediaUploadFiles.applicationSupport())
            ?? MediaUploadFiles(root: FileManager.default.temporaryDirectory.appendingPathComponent("MediaUploads"))
        return MediaUploadQueue(
            store: GRDBMediaUploadStore(database: database),
            files: files,
            server: APIMediaUploadServer(apiClient: apiClient),
            transfer: transfer,
            sessionRefresher: APISessionRefresher(apiClient: apiClient, authSession: authSession),
            analytics: analytics,
            imageLoader: imageLoader,
            runInBackground: { name, work in await UIKitBackgroundTasks().run(name, work) }
        )
    }

    /// The edit sheet's "Photos et vidéos" (and the finish screen's, #185).
    var activityMediaUploads: ActivityMediaUploads {
        let queue = mediaUploadQueue
        return ActivityMediaUploads(board: queue.board) { picked, activityID in
            await queue.enqueue(picked, to: activityID)
        }
    }

    /// The coordinator's triggers (foreground, network back) and the sign-out (ADR-031 §14).
    var mediaUploadSender: QueuedSender {
        let queue = mediaUploadQueue
        return QueuedSender(
            send: { await queue.send(ignoringBackoff: true) },
            stop: { queue.stopPass() },
            clear: { await queue.clear() }
        )
    }

    /// `application(_:handleEventsForBackgroundURLSession:completionHandler:)`: the session
    /// already exists and the queue handles its events since launch.
    func handleEventsForBackgroundURLSession(_ identifier: String, completionHandler: @escaping @Sendable () -> Void) -> Bool {
        mediaTransfer.handleEvents(for: identifier, completionHandler: completionHandler)
    }
}
