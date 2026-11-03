import Foundation

/// Where a Media picked on the finish screen stands before Save writes its row (ADR-037 §6).
enum PreparedExport: Hashable, Sendable {
    case exporting
    case exported(ExportedMedia)
    /// The library could not hand the original (`MediaExporter.Failure.unavailable`).
    case unavailable
    case failed
    /// Save wrote its row while the export was running: the export finishes on that row.
    case saved
}

/// The exports (ADR-037 §3, §5): one at a time in selection order, under a background task.
/// The finish screen's Media start at the selection (`prepare`), before their rows exist; Save
/// writes the rows in its own transaction (`uploads(for:to:)`), then hands them back (`adopt`).
extension MediaUploadQueue {
    // MARK: - Finish screen

    /// The athlete picked these Media on the finish screen: their exports start now, in the app's
    /// container, while the title and visibility are set.
    func prepare(_ picked: [PickedMedia]) {
        for media in picked where prepared[media.id] == nil {
            prepared[media.id] = .exporting
            sources[media.id] = media.source
            exportOrder.append(media.id)
            board.setPreparation(.exporting, of: media.id)
        }
        runExports()
    }

    /// Removed from the strip, or the Recording deleted: the export stops and its files go.
    /// Nothing for a Media already saved.
    func release(_ mediaIDs: [UUID]) {
        let released = mediaIDs.filter { prepared[$0] != nil && prepared[$0] != .saved }
        guard !released.isEmpty else { return }
        exportOrder.removeAll { released.contains($0) }
        for id in released {
            sources[id] = nil
            files.delete(id)
        }
        forgetPrepared(released)
    }

    /// The rows Save writes in its transaction, each at its `position`: `uploading` with its
    /// files when the export is over, `exporting` otherwise.
    func uploads(for picked: [(media: PickedMedia, position: Int)], to activityID: ActivityID) -> [MediaUpload] {
        let date = now()
        return picked.map { item in
            var upload = MediaUpload(
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
            if case .exported(let exported)? = prepared[item.media.id] {
                apply(exported, to: &upload)
            }
            return upload
        }
    }

    /// After Save's commit: the rows are the queue's. An export that ended meanwhile is written
    /// on its row, a failed one turns it "Échec"; a running one finishes on it. They are sent
    /// once their Activity exists on the server (`canSend`).
    func adopt(_ picked: [PickedMedia]) async {
        for media in picked {
            let id = media.id
            let preparation = prepared[id]
            prepared[id] = preparation == .exporting ? .saved : nil
            board.setPreparation(nil, of: id)
            guard var upload = try? await store.upload(id), upload.state == .exporting else { continue }
            switch preparation {
            case .exported(let exported)?:
                apply(exported, to: &upload)
                _ = try? await store.save(upload)
                sources[id] = nil
            case .unavailable?, .failed?:
                await fail(upload, .exportFailed)
            case .exporting?, .saved?:
                continue
            case nil:
                // Never prepared: exported from now on.
                guard sources[id] == nil else { continue }
                sources[id] = media.source
                exportOrder.append(id)
            }
        }
        await refreshBoard()
        runExports()
        await send()
    }

    /// "Réessayer" on a finish screen's tile whose export failed.
    func reprepare(_ mediaID: UUID) {
        guard prepared[mediaID] == .failed || prepared[mediaID] == .unavailable, sources[mediaID] != nil else { return }
        prepared[mediaID] = .exporting
        board.setPreparation(.exporting, of: mediaID)
        exportOrder.append(mediaID)
        runExports()
    }

    func forgetPrepared(_ mediaIDs: [UUID]) {
        for id in mediaIDs where prepared.removeValue(forKey: id) != nil {
            board.setPreparation(nil, of: id)
        }
    }

    // MARK: - Exports

    func runExports() {
        guard exporting == nil, !exportOrder.isEmpty else { return }
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
        guard let source = sources[mediaID] else { return }
        if let upload = try? await store.upload(mediaID) {
            guard upload.state == .exporting else { return }
        } else if prepared[mediaID] == nil {
            return
        }
        let exported: ExportedMedia
        do {
            let directory = try files.makeDirectory(of: mediaID)
            exported = try await exporter.export(source, into: directory)
        } catch {
            files.delete(mediaID)
            await exportFailed(mediaID, unavailable: error as? MediaExporter.Failure == .unavailable)
            return
        }
        await finishExport(mediaID, exported)
    }

    /// Written on the row, then sent once its Activity exists on the server; kept in memory
    /// while Save has not written the row.
    private func finishExport(_ mediaID: UUID, _ exported: ExportedMedia) async {
        guard var upload = try? await savedRow(mediaID) else {
            if prepared[mediaID] == nil {
                // "Retirer" or "Supprimer" during the export.
                files.delete(mediaID)
            } else {
                prepared[mediaID] = .exported(exported)
                sources[mediaID] = nil
                board.setPreparation(.ready, of: mediaID)
            }
            return
        }
        prepared[mediaID] = nil
        guard upload.state == .exporting else { return }
        apply(exported, to: &upload)
        guard (try? await store.save(upload)) == true else {
            files.delete(mediaID)
            return
        }
        sources[mediaID] = nil
        await refreshBoard()
        guard await canSend(upload.activityID) else { return }
        await self.upload(upload)
    }

    private func exportFailed(_ mediaID: UUID, unavailable: Bool) async {
        guard let upload = try? await savedRow(mediaID) else {
            guard prepared[mediaID] != nil else { return }
            prepared[mediaID] = unavailable ? .unavailable : .failed
            board.setPreparation(unavailable ? .unavailable : .failed, of: mediaID)
            return
        }
        prepared[mediaID] = nil
        guard upload.state == .exporting else { return }
        await fail(upload, .exportFailed)
    }

    /// The row of `mediaID`; read again when Save committed it while the first read was queued.
    private func savedRow(_ mediaID: UUID) async throws -> MediaUpload? {
        if let upload = try await store.upload(mediaID) { return upload }
        guard prepared[mediaID] == .saved else { return nil }
        return try await store.upload(mediaID)
    }

    /// The exported files on the row: due for upload now.
    private func apply(_ exported: ExportedMedia, to upload: inout MediaUpload) {
        upload.width = exported.width
        upload.height = exported.height
        upload.durationMs = exported.durationMs
        upload.files = exported.files
        upload.state = .uploading
        upload.attempts = 0
        upload.nextAttemptAt = now()
    }
}
