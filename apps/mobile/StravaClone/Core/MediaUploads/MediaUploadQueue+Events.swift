import Foundation

/// The background session's events (ADR-037 §5) and the board kept in step with the rows.
extension MediaUploadQueue {
    /// One `PUT` moved on or ended, while the app runs or after iOS relaunched it.
    func handle(_ event: MediaTransferEvent) async {
        switch event {
        case .progress(let key, let sent, _):
            sentBytes[key] = sent
            if let upload = rows[key.mediaID], upload.state == .uploading {
                board.setStatus(.sending(progress: progress(of: upload)), of: key.mediaID)
            }
        case .finished(let key, let status):
            await finished(key, status: status)
        case .failed(let key):
            activeFiles.remove(key)
            sentBytes[key] = nil
            guard let upload = try? await store.upload(key.mediaID), upload.state == .uploading else { return }
            await postpone(upload)
            await send()
        }
    }

    private func finished(_ key: MediaFileKey, status: Int) async {
        activeFiles.remove(key)
        sentBytes[key] = nil
        guard var upload = try? await store.upload(key.mediaID), upload.state == .uploading,
              let index = upload.files.firstIndex(where: { $0.name == key.name })
        else { return }
        switch status {
        case 200 ..< 300:
            upload.files[index].uploaded = true
            if upload.filesToUpload.isEmpty {
                upload.state = .confirming
                upload.attempts = 0
            }
            guard (try? await store.save(upload)) == true else { return }
            await refreshBoard()
            if upload.state == .confirming {
                await confirm(upload)
            }
        case 403:
            // The URL expired (or was refused): new URLs, then the file again, a bounded number
            // of times.
            upload.attempts += 1
            guard upload.attempts < Self.maxAttempts else {
                await fail(upload, .network)
                return
            }
            guard (try? await store.save(upload)) == true else { return }
            await self.upload(upload)
        case 500...:
            await postpone(upload)
            await send()
        default:
            await fail(upload, .invalid)
        }
    }

    /// The share of the Media's bytes already in the bucket.
    func progress(of upload: MediaUpload) -> Double {
        let total = upload.files.reduce(0) { $0 + $1.byteCount }
        guard total > 0 else { return 0 }
        let sent = upload.files.reduce(Int64(0)) { sum, file in
            sum + (file.uploaded ? Int64(file.byteCount) : min(sentBytes[key(upload, file)] ?? 0, Int64(file.byteCount)))
        }
        return min(1, Double(sent) / Double(total))
    }

    /// Every row as a local Media of its Activity, with its status.
    func refreshBoard() async {
        let all = (try? await store.all()) ?? []
        rows = Dictionary(all.map { ($0.mediaID, $0) }, uniquingKeysWith: { first, _ in first })
        var entries: [ActivityID: [MediaUploadBoard.Entry]] = [:]
        for upload in all {
            entries[upload.activityID, default: []].append(MediaUploadBoard.Entry(position: upload.position, media: localMedia(upload)))
        }
        board.show(entries)
    }

    /// "Réessayer" is offered when the files can be sent again, or the original exported again;
    /// never for an original only in iCloud, picked offline (ADR-037 §6).
    private func canRetry(_ upload: MediaUpload) -> Bool {
        upload.failure != .unavailableOffline && (upload.isExported || canReexport(upload.mediaID))
    }

    private func localMedia(_ upload: MediaUpload) -> ActivityMedia {
        let status: MediaUploadStatus = switch upload.state {
        case .exporting: .exporting
        case .uploading: .sending(progress: progress(of: upload))
        case .confirming: .sending(progress: 1)
        case .failed: .failed(upload.failure ?? .network, canRetry: canRetry(upload))
        }
        let original = upload.kind == .photo ? MediaUploadFile.originalPhoto : MediaUploadFile.originalVideo
        return ActivityMedia(
            id: upload.mediaID,
            kind: upload.kind,
            width: upload.width ?? 0,
            height: upload.height ?? 0,
            duration: upload.durationMs.map { .milliseconds($0) },
            url: files.url(of: original, mediaID: upload.mediaID),
            posterURL: upload.kind == .video ? files.url(of: MediaUploadFile.poster, mediaID: upload.mediaID) : nil,
            thumbURL: files.url(of: MediaUploadFile.thumb, mediaID: upload.mediaID),
            upload: status
        )
    }
}
