import Foundation

/// A photo or video of an Activity as every screen gets it (ADR-037 §7): the feed card, the
/// detail, the viewer and the Gallery. Lives in Core because Feed, ActivityDetail and Profile all
/// show Media (ADR-007 rule 5).
///
/// The URLs are 1-hour pre-signed `GET`s: `ImageLoader` caches by path, and a `403` reloads the
/// screen for fresh ones (ADR-037 §1). Which URL a screen shows is in ADR-037 §7: `url` for a photo
/// and `posterURL` then `url` for a video in the carousel and viewer, `thumbURL` in the Gallery.
struct ActivityMedia: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case photo
        case video
    }

    let id: UUID
    let kind: Kind
    /// Pixel size of `url`, as the iPhone measured it.
    let width: Int
    let height: Int
    /// Nil for a photo.
    let duration: Duration?
    /// The photo (2048 px) or the MP4 video.
    let url: URL
    /// The first frame of a video (1280 px); nil for a photo.
    let posterURL: URL?
    /// 512 px, for the Gallery grid and the edit strip.
    let thumbURL: URL
    /// Set on the author's phone while the Media is still being sent (ADR-037 §5, §6): its URLs
    /// are then local files, and the carousel adds a progress ring or "Échec". Nil once
    /// confirmed, and for every Media the API returns.
    var upload: MediaUploadStatus? = nil
}

extension ActivityMedia {
    /// The still image of the carousel and viewer (ADR-037 §7): a video's poster, else the photo.
    var stillURL: URL? { kind == .video ? posterURL : url }
}

/// A Media not confirmed yet, as the author's screens show it (ADR-037 §5).
enum MediaUploadStatus: Hashable, Sendable {
    /// The library original is being converted: no local file to show yet.
    case exporting
    /// Its files are going to the bucket, then confirmed: `progress` from 0 to 1.
    case sending(progress: Double)
    /// "Échec": "Réessayer" (when the files can still be sent) and "Retirer".
    case failed(MediaUploadFailure, canRetry: Bool)
}
