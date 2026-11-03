import Foundation

/// The upload queue of ADR-037 §5: every Media goes `exporting` → `uploading` → `confirming`,
/// then its row and local files are deleted after the `201`; or it turns `failed`. Exports run
/// one at a time in selection order under a background task, and each upload starts as soon as
/// its export ends, through the background `URLSession` (`MediaFileTransferring`). The rows are
/// read at launch (`resume`) and on each trigger of the queue coordinator (`send`), and the
/// session's events are handled as they come, after a relaunch by iOS too.
///
/// Failure table:
/// - `403` from the bucket (URL expired): `upload-urls` again, then a new `PUT`;
/// - 5xx, no network, no answer: backoff, "Échec" (`network`) at the 5th in a row;
/// - `401`: the session is refreshed, then the call is sent again;
/// - `409 media_missing` on confirmation: the files are sent again;
/// - `409 media_limit_reached`: "Échec" (`limit_reached`) at once;
/// - `422`, `409 media_invalid` / `media_id_taken`, another bucket refusal: "Échec" (`invalid`);
/// - export impossible: "Échec" (`export_failed`);
/// - `404` (Activity deleted): silent abandon, row and files deleted.
///
/// Generic on the kind (the exporter decides) and on the Activity's state: `canSend` holds a
/// row back while its Activity does not exist on the server yet (#185).
@MainActor
final class MediaUploadQueue {
    static let maxAttempts = 5

    let board: MediaUploadBoard
    let store: GRDBMediaUploadStore
    let files: MediaUploadFiles
    let transfer: any MediaFileTransferring
    let server: any MediaUploadServer
    private let exporter: MediaExporter
    private let sessionRefresher: any SessionRefreshing
    private let analytics: any AnalyticsClient
    private let imageLoader: ImageLoader?
    private let backoff: RetryBackoff
    let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void
    private let runInBackground: MediaBackgroundWork
    private let canSend: @MainActor (ActivityID) async -> Bool

    /// The library originals not exported yet, or whose export failed ("Réessayer").
    private var sources: [UUID: MediaSource] = [:]
    private var exportOrder: [UUID] = []
    private var exporting: Task<Void, Never>?
    /// Files with a `PUT` running in the session.
    var activeFiles: Set<MediaFileKey> = []
    /// Bytes sent so far of the running `PUT`s, for the progress ring.
    var sentBytes: [MediaFileKey: Int64] = [:]
    /// Media with an API call in flight: a pass and an event never send the same one twice.
    private var inFlight: Set<UUID> = []
    /// The rows as last read, for the progress events.
    var rows: [UUID: MediaUpload] = [:]
    private var sending: Task<Void, Never>?
    private var rerun = false
    private var rerunIgnoringBackoff = false
    private var wakeUp: Task<Void, Never>?
    private var observing: Task<Void, Never>?

    init(
        store: GRDBMediaUploadStore,
        files: MediaUploadFiles,
        server: any MediaUploadServer,
        transfer: any MediaFileTransferring,
        sessionRefresher: any SessionRefreshing,
        analytics: any AnalyticsClient,
        board: MediaUploadBoard = MediaUploadBoard(),
        exporter: MediaExporter = MediaExporter(),
        imageLoader: ImageLoader? = nil,
        backoff: RetryBackoff = RetryBackoff(initialDelay: .seconds(2), maxDelay: .seconds(300)),
        now: @escaping @Sendable () -> Date = Date.init,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        runInBackground: @escaping MediaBackgroundWork = { _, work in await work() },
        canSend: @escaping @MainActor (ActivityID) async -> Bool = { _ in true }
    ) {
        self.store = store
        self.files = files
        self.server = server
        self.transfer = transfer
        self.sessionRefresher = sessionRefresher
        self.analytics = analytics
        self.board = board
        self.exporter = exporter
        self.imageLoader = imageLoader
        self.backoff = backoff
        self.now = now
        self.sleep = sleep
        self.runInBackground = runInBackground
        self.canSend = canSend
        board.retry = { [weak self] id in Task { await self?.retry(id) } }
        board.remove = { [weak self] id in Task { await self?.remove(id) } }
    }

    // MARK: - Lifecycle

    /// At launch: the session's events are handled from now on, then the rows are read again.
    func start() async {
        if observing == nil {
            let events = transfer.events
            observing = Task { [weak self] in
                for await event in events {
                    await self?.handle(event)
                }
            }
        }
        await resume()
    }

    /// The rows left by a previous run: an export the app's death cut is lost (row and files
    /// deleted silently, ADR-037 §5); the others go on where they stopped, the files with a
    /// task still running in the session excepted.
    func resume() async {
        let all = (try? await store.all()) ?? []
        let lost = all.filter { $0.state == .exporting && sources[$0.mediaID] == nil }
        try? await store.delete(lost.map(\.mediaID))
        let kept = Set(all.map(\.mediaID)).subtracting(lost.map(\.mediaID))
        files.deleteFolders(except: kept)
        activeFiles = await transfer.activeFiles()
        await refreshBoard()
        await send()
    }

    // MARK: - Screens

    /// "Enregistrer": one `exporting` row per Media, at its index in the Activity's order, then
    /// the exports start in this order.
    func enqueue(_ picked: [(media: PickedMedia, position: Int)], to activityID: ActivityID) async {
        guard !picked.isEmpty else { return }
        let date = now()
        let uploads = picked.map { item in
            MediaUpload(
                mediaID: item.media.id,
                activityID: activityID,
                kind: item.media.kind,
                position: item.position,
                state: .exporting,
                failure: nil,
                files: [],
                attempts: 0,
                nextAttemptAt: date,
                createdAt: date
            )
        }
        do {
            try await store.insert(uploads)
        } catch {
            return
        }
        for item in picked {
            sources[item.media.id] = item.media.source
            exportOrder.append(item.media.id)
        }
        await refreshBoard()
        runExports()
    }

    /// "Réessayer" on a failed tile: the files are sent again, or the export runs again while
    /// the library original is still in memory.
    func retry(_ mediaID: UUID) async {
        guard var upload = try? await store.upload(mediaID), upload.state == .failed else { return }
        if upload.isExported {
            upload.state = upload.filesToUpload.isEmpty ? .confirming : .uploading
        } else if sources[mediaID] != nil {
            upload.state = .exporting
            exportOrder.append(mediaID)
        } else {
            return
        }
        upload.failure = nil
        upload.attempts = 0
        upload.nextAttemptAt = now()
        _ = try? await store.save(upload)
        await refreshBoard()
        if upload.state == .exporting {
            runExports()
        } else {
            await send()
        }
    }

    /// "Retirer": tasks cancelled, row and local files deleted. Objects already in the bucket
    /// are left to the `bucket-sweep` (ADR-037 §11).
    func remove(_ mediaID: UUID) async {
        await discard([mediaID])
    }

    /// Sign-out: every row, file and task goes (#186).
    func clear() async {
        wakeUp?.cancel()
        wakeUp = nil
        exportOrder = []
        sources = [:]
        await transfer.cancelAll()
        activeFiles = []
        sentBytes = [:]
        try? await store.deleteAll()
        files.deleteAll()
        rows = [:]
        board.clear()
    }

    /// iOS takes the background time back: the scheduled retry is cancelled. The `PUT`s go on
    /// in the session.
    func stopPass() {
        wakeUp?.cancel()
        wakeUp = nil
        sending?.cancel()
    }

    // MARK: - Exports

    private func runExports() {
        guard exporting == nil else { return }
        exporting = Task {
            await runInBackground("media-export") {
                while !exportOrder.isEmpty {
                    let mediaID = exportOrder.removeFirst()
                    await export(mediaID)
                }
            }
            exporting = nil
        }
    }

    private func export(_ mediaID: UUID) async {
        guard let source = sources[mediaID], var upload = try? await store.upload(mediaID), upload.state == .exporting else {
            return
        }
        let exported: ExportedMedia
        do {
            let directory = try files.makeDirectory(of: mediaID)
            exported = try await exporter.export(source, into: directory)
        } catch {
            files.delete(mediaID)
            await fail(upload, .exportFailed)
            return
        }
        upload.width = exported.width
        upload.height = exported.height
        upload.durationMs = exported.durationMs
        upload.files = exported.files
        upload.state = .uploading
        upload.attempts = 0
        upload.nextAttemptAt = now()
        guard (try? await store.save(upload)) == true else {
            // "Retirer" during the export.
            files.delete(mediaID)
            return
        }
        sources[mediaID] = nil
        await refreshBoard()
        guard await canSend(upload.activityID) else { return }
        await self.upload(upload)
    }

    // MARK: - Passes

    /// Sends what is due, or everything pending when `ignoringBackoff` (network back,
    /// foreground). Joins the pass already running.
    func send(ignoringBackoff: Bool = false) async {
        if let sending {
            rerun = true
            rerunIgnoringBackoff = rerunIgnoringBackoff || ignoringBackoff
            await sending.value
            return
        }
        let task = Task { await self.run(ignoringBackoff: ignoringBackoff) }
        sending = task
        await task.value
    }

    private func run(ignoringBackoff: Bool) async {
        var ignoringBackoff = ignoringBackoff
        repeat {
            rerun = false
            await sendPending(ignoringBackoff: ignoringBackoff)
            ignoringBackoff = rerunIgnoringBackoff
            rerunIgnoringBackoff = false
        } while rerun
        sending = nil
        guard !Task.isCancelled else { return }
        await scheduleWakeUp()
    }

    private func sendPending(ignoringBackoff: Bool) async {
        guard let all = try? await store.all() else { return }
        let date = now()
        for upload in all where upload.state == .uploading || upload.state == .confirming {
            guard !Task.isCancelled else { return }
            guard ignoringBackoff || SyncQueueSchedule.isDue(upload.nextAttemptAt, at: date) else { continue }
            guard await canSend(upload.activityID) else { continue }
            if upload.state == .uploading {
                await self.upload(upload)
            } else {
                await confirm(upload)
            }
        }
    }

    /// `upload-urls` for the Media's full set, then a `PUT` for each file neither sent nor
    /// running. Every file sent: the confirmation.
    func upload(_ upload: MediaUpload) async {
        guard !upload.filesToUpload.isEmpty else {
            var confirming = upload
            confirming.state = .confirming
            guard (try? await store.save(confirming)) == true else { return }
            await confirm(confirming)
            return
        }
        let missing = upload.filesToUpload.filter { !activeFiles.contains(key(upload, $0)) }
        guard !missing.isEmpty, inFlight.insert(upload.mediaID).inserted else { return }
        defer { inFlight.remove(upload.mediaID) }
        switch await attempt({ () async throws(MediaServerError) in try await self.server.uploadTargets(for: upload) }) {
        case .success(let targets):
            // Removed, or failed, while the URLs were asked for.
            guard let current = try? await store.upload(upload.mediaID), current.state == .uploading else { return }
            for file in missing {
                guard let target = targets.first(where: { $0.name == file.name }) else { continue }
                let key = key(upload, file)
                activeFiles.insert(key)
                sentBytes[key] = 0
                await transfer.start(MediaFilePut(
                    key: key,
                    file: files.url(of: file.name, mediaID: upload.mediaID),
                    destination: target.url,
                    contentType: file.contentType,
                    contentLength: file.byteCount
                ))
            }
        case .failure(let error):
            await handle(error, of: upload)
        }
    }

    /// `POST /v1/activities/:id/media`: on `201`, the row and the files go and the board shows
    /// the confirmed Media.
    func confirm(_ upload: MediaUpload) async {
        guard inFlight.insert(upload.mediaID).inserted else { return }
        defer { inFlight.remove(upload.mediaID) }
        switch await attempt({ () async throws(MediaServerError) in try await self.server.confirm(upload) }) {
        case .success(let media):
            await prime(media, from: upload)
            try? await store.delete([upload.mediaID])
            files.delete(upload.mediaID)
            board.confirm(media, position: upload.position, of: upload.activityID)
            await refreshBoard()
        case .failure(.refused("media_missing")):
            var again = upload
            again.attempts += 1
            guard again.attempts < Self.maxAttempts else {
                await fail(upload, .network)
                return
            }
            again.state = .uploading
            again.files = again.files.map { file in
                var file = file
                file.uploaded = false
                return file
            }
            guard (try? await store.save(again)) == true else { return }
            await refreshBoard()
            inFlight.remove(upload.mediaID)
            await self.upload(again)
        case .failure(let error):
            await handle(error, of: upload)
        }
    }

    // MARK: - Outcomes

    /// A failed API call, by the failure table.
    private func handle(_ error: MediaServerError, of upload: MediaUpload) async {
        switch error {
        case .notFound:
            await discard([upload.mediaID])
        case .refused("media_limit_reached"):
            await fail(upload, .limitReached)
        case .refused:
            await fail(upload, .invalid)
        case .offline, .unavailable, .unauthorized:
            await postpone(upload)
        }
    }

    /// One more failure in a row: retried after the backoff, "Échec" at the 5th.
    func postpone(_ upload: MediaUpload) async {
        var postponed = upload
        postponed.attempts += 1
        guard postponed.attempts < Self.maxAttempts else {
            await fail(upload, .network)
            return
        }
        let delay = backoff.delay(beforeRetry: postponed.attempts - 1)
        postponed.nextAttemptAt = now().addingTimeInterval(delay.timeInterval)
        try? await store.save(postponed)
        await refreshBoard()
    }

    /// "Échec": the tile waits for "Réessayer" or "Retirer"; `media_upload_failed` is sent.
    func fail(_ upload: MediaUpload, _ reason: MediaUploadFailure) async {
        var failed = upload
        failed.state = .failed
        failed.failure = reason
        guard (try? await store.save(failed)) == true else { return }
        await cancelTasks(of: [upload.mediaID])
        analytics.capture(.mediaUploadFailed(kind: upload.kind, reason: reason))
        await refreshBoard()
    }

    /// Rows, files and tasks of these Media go, nothing is reported.
    func discard(_ mediaIDs: [UUID]) async {
        exportOrder.removeAll { mediaIDs.contains($0) }
        for id in mediaIDs {
            sources[id] = nil
        }
        await cancelTasks(of: mediaIDs)
        try? await store.delete(mediaIDs)
        for id in mediaIDs {
            files.delete(id)
            board.forget(id)
        }
        await refreshBoard()
    }

    private func cancelTasks(of mediaIDs: [UUID]) async {
        let ids = Set(mediaIDs)
        await transfer.cancel(mediaIDs: ids)
        activeFiles = activeFiles.filter { !ids.contains($0.mediaID) }
        sentBytes = sentBytes.filter { !ids.contains($0.key.mediaID) }
    }

    /// The request, sent once more after a `401` if the session could be refreshed.
    func attempt<T>(_ request: @escaping () async throws(MediaServerError) -> T) async -> Result<T, MediaServerError> {
        let result = await Self.result(of: request)
        guard case .failure(.unauthorized) = result, await sessionRefresher.refresh() else { return result }
        return await Self.result(of: request)
    }

    private static func result<T>(of request: () async throws(MediaServerError) -> T) async -> Result<T, MediaServerError> {
        do throws(MediaServerError) {
            return .success(try await request())
        } catch {
            return .failure(error)
        }
    }

    /// The local files become the cache of the remote URLs: no blank between the local image
    /// and the confirmed one.
    private func prime(_ media: ActivityMedia, from upload: MediaUpload) async {
        guard let imageLoader else { return }
        let original = upload.kind == .photo ? MediaUploadFile.originalPhoto : MediaUploadFile.poster
        let remoteOriginal = upload.kind == .photo ? media.url : media.posterURL
        if let remoteOriginal {
            await imageLoader.store(contentsOf: files.url(of: original, mediaID: upload.mediaID), as: remoteOriginal)
        }
        await imageLoader.store(contentsOf: files.url(of: MediaUploadFile.thumb, mediaID: upload.mediaID), as: media.thumbURL)
    }

    /// The library original of a failed export is still in memory.
    func canReexport(_ mediaID: UUID) -> Bool {
        sources[mediaID] != nil
    }

    func key(_ upload: MediaUpload, _ file: MediaUploadFile) -> MediaFileKey {
        MediaFileKey(mediaID: upload.mediaID, name: file.name)
    }

    private func scheduleWakeUp() async {
        wakeUp?.cancel()
        wakeUp = nil
        let date = now()
        let due = rows.values
            .filter { ($0.state == .uploading || $0.state == .confirming) && $0.attempts > 0 }
            .map(\.nextAttemptAt)
            .filter { $0 > date }
        guard let next = due.min() else { return }
        let sleep = sleep
        wakeUp = Task { [weak self] in
            guard (try? await sleep(.seconds(next.timeIntervalSince(date)))) != nil, !Task.isCancelled else { return }
            await self?.send()
        }
    }
}
