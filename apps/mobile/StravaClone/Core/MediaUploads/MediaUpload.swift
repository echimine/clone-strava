import Foundation

/// Where a Media being sent stands (ADR-037 §5): `exporting` → `uploading` → `confirming`, or
/// `failed`. The row is deleted after the confirmation's `201`, so there is no "sent" state.
enum MediaUploadState: String, Codable, Hashable, Sendable {
    /// The library original is turned into the files to send (JPEG, MP4, previews).
    case exporting
    /// The files go to the bucket through the background `URLSession`.
    case uploading
    /// Every file is in the bucket: `POST /v1/activities/:id/media` is due.
    case confirming
    /// "Échec": waits for "Réessayer" or "Retirer".
    case failed
}

/// Why a tile turned "Échec", stored on its row; `analyticsReason` is the `reason` of
/// `media_upload_failed` (ADR-037 §13).
enum MediaUploadFailure: String, Codable, Hashable, Sendable {
    /// 5xx or no network, 5 times in a row.
    case network
    /// `409 media_limit_reached`: the Activity already has 8 Media.
    case limitReached = "limit_reached"
    /// `422`, `409 media_invalid` or `media_id_taken`, or a bucket refusal other than `403`.
    case invalid
    /// The library original could not be read or converted.
    case exportFailed = "export_failed"
    /// The original is only in iCloud and was picked offline: "Média indisponible hors
    /// connexion", with "Retirer" only (ADR-037 §6). Reported as `export_failed`.
    case unavailableOffline = "unavailable_offline"

    /// The `reason` of `media_upload_failed` (ADR-037 §13).
    var analyticsReason: String {
        switch self {
        case .unavailableOffline: MediaUploadFailure.exportFailed.rawValue
        default: rawValue
        }
    }
}

/// One file of a Media, named as the API expects (`MEDIA_FILES`, ADR-037 §3).
struct MediaUploadFile: Codable, Hashable, Sendable {
    /// `original.jpg`, `original.mp4`, `poster.jpg` or `thumb.jpg`.
    let name: String
    /// `image/jpeg` or `video/mp4`: signed into the `PUT`, sent exactly.
    let contentType: String
    /// Exact size in bytes: signed into the `PUT` as `Content-Length`.
    let byteCount: Int
    /// The bucket answered `2xx` to its `PUT`. Reset by `409 media_missing`.
    var uploaded = false

    static let originalPhoto = "original.jpg"
    static let originalVideo = "original.mp4"
    static let poster = "poster.jpg"
    static let thumb = "thumb.jpg"
}

/// One row of `media_upload` (migration `media_upload_v1`).
struct MediaUpload: Hashable, Sendable {
    let mediaID: UUID
    let activityID: ActivityID
    let kind: ActivityMedia.Kind
    /// Index in the Activity's Media order (ADR-037 §8), sent as `position` on confirmation.
    var position: Int
    var state: MediaUploadState
    var failure: MediaUploadFailure?
    /// Known once exported.
    var width: Int?
    var height: Int?
    var durationMs: Int?
    /// Empty until exported.
    var files: [MediaUploadFile]
    /// Network failures in a row (backoff, "Échec" at 5).
    var attempts: Int
    var nextAttemptAt: Date
    let createdAt: Date

    var isExported: Bool { !files.isEmpty && width != nil && height != nil }

    /// Files whose `PUT` has not succeeded yet.
    var filesToUpload: [MediaUploadFile] { files.filter { !$0.uploaded } }
}

/// A Media picked in the library, before it is exported (ADR-037 §3, §5). Built by the screen
/// from a `PhotosPickerItem`; the queue only reads it, in the app's memory: if the app is killed
/// during the export, the Media is lost (no copy of the library original is kept).
struct MediaSource: Sendable {
    enum Content: Sendable {
        /// The image's bytes (HEIC, JPEG…; a Live Photo's key still).
        case image(Data)
        /// A movie file the exporter may read.
        case movie(URL)
    }

    let kind: ActivityMedia.Kind
    /// A picked video's copy, for its tile and `videosTrimmed`; nil for a photo.
    let movie: PickedMovie?
    let load: @Sendable () async throws -> Content

    init(kind: ActivityMedia.Kind, movie: PickedMovie? = nil, load: @escaping @Sendable () async throws -> Content) {
        self.kind = kind
        self.movie = movie
        self.load = load
    }
}

/// A Media picked on a screen, before its row exists: `id` is the future `mediaId`, made by the
/// phone, so the screen can already place it in `mediaOrder` (ADR-037 §8).
struct PickedMedia: Identifiable, Sendable {
    let id: UUID
    let source: MediaSource

    init(id: UUID = UUID(), source: MediaSource) {
        self.id = id
        self.source = source
    }

    var kind: ActivityMedia.Kind { source.kind }
}

/// Work kept going for a while once the app leaves the foreground (`beginBackgroundTask`).
typealias MediaBackgroundWork = @MainActor (_ name: String, _ work: @MainActor () async -> Void) async -> Void

/// What the exporter wrote in a Media's folder.
struct ExportedMedia: Hashable, Sendable {
    let width: Int
    let height: Int
    /// Nil for a photo.
    let durationMs: Int?
    let files: [MediaUploadFile]
}
