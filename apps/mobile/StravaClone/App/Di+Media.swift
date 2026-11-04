import Foundation

/// The Media of an Activity (ADR-037 §5): the queue of `media_upload`, its background session
/// and what the screens get of it.
extension Di {
    /// The queue over the app's background session, its files in Application Support. The
    /// session must exist at launch: iOS hands it the events of uploads finished meanwhile. A
    /// row waits until the server has its Activity, and while its Delete waits (ADR-037 §6).
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
            canSend: { activityID in await localActivities.canSendMedia(of: activityID) }
        )
    }

    /// The "Photos et vidéos" of the edit sheet and of the finish screen.
    var activityMediaUploads: ActivityMediaUploads {
        ActivityMediaUploads(queue: mediaUploadQueue, analytics: analytics)
    }

    /// The coordinator's triggers (foreground, network back) and the sign-out (ADR-031 §14).
    var mediaUploadSender: QueuedSender {
        Self.mediaUploadSender(queue: mediaUploadQueue, localActivities: localActivities)
    }

    /// `queue` on the coordinator's triggers, following the local Activities (ADR-037 §6).
    static func mediaUploadSender(queue: MediaUploadQueue, localActivities: GRDBLocalActivityStore) -> QueuedSender {
        QueuedSender(
            send: { await queue.send(ignoringBackoff: true) },
            stop: { queue.stopPass() },
            clear: { await queue.clear() },
            // The finish screen's Media were waiting for their Activity.
            activityCreated: { _ in await queue.send() },
            activityDeletion: { activityID, deletion in
                switch deletion {
                case .pending: await queue.hold(mediaOf: activityID)
                case .deleted: await queue.discard(mediaOf: activityID)
                // Back in `processing`: its Media go on, without holding up the Activities' pass.
                case .refused: Task { await queue.send(ignoringBackoff: true) }
                }
            },
            unsentCount: {
                let givenUp = (try? await localActivities.activityIDsBeingDeleted()) ?? []
                return await queue.unsentCount(excluding: givenUp)
            }
        )
    }

    /// `application(_:handleEventsForBackgroundURLSession:completionHandler:)`: the session
    /// already exists and the queue handles its events since launch.
    func handleEventsForBackgroundURLSession(_ identifier: String, completionHandler: @escaping @Sendable () -> Void) -> Bool {
        mediaTransfer.handleEvents(for: identifier, completionHandler: completionHandler)
    }
}
