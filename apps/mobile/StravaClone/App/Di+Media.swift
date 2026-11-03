import Foundation

/// The Media of an Activity (ADR-037 §5): the queue of `media_upload`, its background session
/// and what the screens get of it.
extension Di {
    /// The queue over the app's background session, its files in Application Support. The
    /// session must exist at launch: iOS hands it the events of uploads finished meanwhile. A
    /// row waits until the server has its Activity (ADR-037 §6).
    static func makeMediaUploadQueue(
        database: AppDatabase,
        localActivities: GRDBLocalActivityStore,
        apiClient: APIClient,
        authSession: AuthSession,
        analytics: any AnalyticsClient,
        imageLoader: ImageLoader,
        transfer: BackgroundMediaTransfer
    ) -> MediaUploadQueue {
        // No picked video outlives the app: the copies a killed run left go.
        PickedMovie.deleteLeftovers()
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
            runInBackground: { name, work in await UIKitBackgroundTasks().run(name, work) },
            canSend: { activityID in await localActivities.isKnownToServer(activityID) }
        )
    }

    /// The "Photos et vidéos" of the edit sheet and of the finish screen.
    var activityMediaUploads: ActivityMediaUploads {
        ActivityMediaUploads(queue: mediaUploadQueue, analytics: analytics)
    }

    /// The coordinator's triggers (foreground, network back) and the sign-out (ADR-031 §14).
    var mediaUploadSender: QueuedSender {
        let queue = mediaUploadQueue
        return QueuedSender(
            send: { await queue.send(ignoringBackoff: true) },
            stop: { queue.stopPass() },
            clear: { await queue.clear() },
            // The finish screen's Media were waiting for their Activity (ADR-037 §6).
            activityCreated: { _ in await queue.send() }
        )
    }

    /// `application(_:handleEventsForBackgroundURLSession:completionHandler:)`: the session
    /// already exists and the queue handles its events since launch.
    func handleEventsForBackgroundURLSession(_ identifier: String, completionHandler: @escaping @Sendable () -> Void) -> Bool {
        mediaTransfer.handleEvents(for: identifier, completionHandler: completionHandler)
    }
}
