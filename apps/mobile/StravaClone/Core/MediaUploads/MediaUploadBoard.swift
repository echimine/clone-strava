import Foundation
import Observation
import SwiftUI

/// What the author's screens show of the Media being sent (ADR-037 §5, §6), kept by
/// `MediaUploadQueue`: each `media_upload` row as a local `ActivityMedia` with its status, and
/// the Media confirmed during this launch, until the screens' own copy (feed, detail) carries
/// them. The carousels merge it into the API's Media (`media(of:merging:)`): only the author's
/// phone has rows, so another athlete's Activity is never changed.
@Observable
@MainActor
final class MediaUploadBoard {
    /// A local Media at its index in the Activity's order.
    struct Entry: Hashable, Sendable {
        let position: Int
        let media: ActivityMedia
    }

    /// A Media picked on the finish screen, exported before Save writes its row (ADR-037 §6).
    enum Preparation: Hashable, Sendable {
        case exporting
        case ready
        /// The library could not hand the original (only in iCloud, picked offline): "Média
        /// indisponible hors connexion", with "Retirer" only.
        case unavailable
        /// The original could not be converted: "Réessayer" and "Retirer".
        case failed
    }

    private(set) var pending: [ActivityID: [Entry]] = [:]
    private(set) var confirmed: [ActivityID: [Entry]] = [:]
    private(set) var preparations: [UUID: Preparation] = [:]

    /// "Réessayer" and "Retirer" on a failed tile, set by the queue.
    @ObservationIgnored var retry: @MainActor (UUID) -> Void = { _ in }
    @ObservationIgnored var remove: @MainActor (UUID) -> Void = { _ in }

    init() {}

    /// The API's Media of `activityID` with the local ones placed at their index; a local Media
    /// the API already returns is dropped, so a confirmed Media never shows twice.
    func media(of activityID: ActivityID, merging remote: [ActivityMedia]) -> [ActivityMedia] {
        let local = (confirmed[activityID] ?? []) + (pending[activityID] ?? [])
        guard !local.isEmpty else { return remote }
        return Self.merge(remote: remote, local: local)
    }

    /// Media of `activityID` still being sent, failed ones included.
    func pendingCount(of activityID: ActivityID) -> Int {
        pending[activityID]?.count ?? 0
    }

    /// Ids of the Media of `activityID` that still have a `media_upload` row.
    func pendingIDs(of activityID: ActivityID) -> Set<UUID> {
        Set((pending[activityID] ?? []).map(\.media.id))
    }

    /// Locals in `position` order, each inserted at its index (or at the end), after the
    /// remote ones it does not duplicate.
    nonisolated static func merge(remote: [ActivityMedia], local: [Entry]) -> [ActivityMedia] {
        let remoteIDs = Set(remote.map(\.id))
        var seen = Set<UUID>()
        let locals = local
            .filter { !remoteIDs.contains($0.media.id) && seen.insert($0.media.id).inserted }
            .sorted { $0.position < $1.position }
        var merged = remote
        for entry in locals {
            merged.insert(entry.media, at: min(max(entry.position, 0), merged.count))
        }
        return merged
    }

    /// Where the export of a Media picked on the finish screen stands; nil once saved, or for a
    /// Media of the edit sheet (exported after "Enregistrer").
    func preparation(of mediaID: UUID) -> Preparation? {
        preparations[mediaID]
    }

    // MARK: - Written by the queue

    func setPreparation(_ preparation: Preparation?, of mediaID: UUID) {
        preparations[mediaID] = preparation
    }

    func show(_ entries: [ActivityID: [Entry]]) {
        pending = entries
    }

    func setStatus(_ status: MediaUploadStatus, of mediaID: UUID) {
        for (activityID, entries) in pending {
            guard let index = entries.firstIndex(where: { $0.media.id == mediaID }) else { continue }
            var media = entries[index].media
            guard media.upload != status else { return }
            media.upload = status
            pending[activityID]?[index] = Entry(position: entries[index].position, media: media)
            return
        }
    }

    /// The `201`: shown with its remote URLs until the screen's copy has it.
    func confirm(_ media: ActivityMedia, position: Int, of activityID: ActivityID) {
        pending[activityID]?.removeAll { $0.media.id == media.id }
        confirmed[activityID, default: []].removeAll { $0.media.id == media.id }
        confirmed[activityID, default: []].append(Entry(position: position, media: media))
    }

    /// A new order (#184): each local Media listed takes its index (`positions`).
    func reorder(_ positions: [UUID: Int], of activityID: ActivityID) {
        pending[activityID] = pending[activityID].map { Self.moved($0, to: positions) }
        confirmed[activityID] = confirmed[activityID].map { Self.moved($0, to: positions) }
    }

    private nonisolated static func moved(_ entries: [Entry], to positions: [UUID: Int]) -> [Entry] {
        entries.map { Entry(position: positions[$0.media.id] ?? $0.position, media: $0.media) }
    }

    /// A confirmed Media deleted since (`DELETE …/media/:mediaId`, #184), or a row removed.
    func forget(_ mediaID: UUID) {
        for activityID in confirmed.keys {
            confirmed[activityID]?.removeAll { $0.media.id == mediaID }
        }
        for activityID in pending.keys {
            pending[activityID]?.removeAll { $0.media.id == mediaID }
        }
    }

    func clear() {
        pending = [:]
        confirmed = [:]
        preparations = [:]
    }
}

extension EnvironmentValues {
    /// The author's Media being sent, injected by the app root; nil in previews and tests.
    @Entry var mediaUploads: MediaUploadBoard?
}
