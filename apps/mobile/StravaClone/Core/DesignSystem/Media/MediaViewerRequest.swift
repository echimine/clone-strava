import Foundation

/// The Activity a Media of the viewer belongs to: its date on top, and, from the Gallery, the
/// "titre · Voir l'activité ›" pill (ADR-037 §9, §10).
struct MediaViewerActivity: Hashable, Sendable {
    let id: ActivityID
    let title: String
    let startedAt: Date
}

/// One Media in the viewer, with its Activity.
struct MediaViewerItem: Identifiable, Hashable, Sendable {
    let media: ActivityMedia
    let activity: MediaViewerActivity

    var id: UUID { media.id }
}

/// What the full-screen viewer shows (ADR-037 §10): a list of Media, the one it opens on, and
/// how it reads. From a carousel (feed, Activités tab, detail): the Activity's Media without
/// the map, "3 sur 8" and the date on top. From the Gallery: any list of Media, no "n sur N",
/// and a pill at the bottom that opens the Media's Activity.
struct MediaViewerRequest: Identifiable, Equatable, Sendable {
    enum Mode: Equatable, Sendable {
        /// "3 sur 8" and the date on top.
        case activity
        /// The date on top, "titre · Voir l'activité ›" at the bottom.
        case gallery
    }

    let id = UUID()
    let items: [MediaViewerItem]
    /// Index in `items` of the Media touched.
    let start: Int
    let mode: Mode

    /// Nil when `media` is not in `items` (it was removed by a refresh) or `items` is empty.
    init?(items: [MediaViewerItem], at media: ActivityMedia, mode: Mode) {
        guard let start = items.firstIndex(where: { $0.media.id == media.id }) else { return nil }
        self.items = items
        self.start = start
        self.mode = mode
    }

    /// The Media of `post`, the map left out, opened on `media`.
    static func activity(_ post: ActivityPost, at media: ActivityMedia) -> MediaViewerRequest? {
        let activity = MediaViewerActivity(id: post.id, title: post.title, startedAt: post.startedAt)
        return MediaViewerRequest(
            items: post.media.map { MediaViewerItem(media: $0, activity: activity) },
            at: media,
            mode: .activity
        )
    }

    /// The Gallery's Media (several Activities), opened on `media`.
    static func gallery(_ items: [MediaViewerItem], at media: ActivityMedia) -> MediaViewerRequest? {
        MediaViewerRequest(items: items, at: media, mode: .gallery)
    }

    /// "3 sur 8" for the Media at `index`; nil from the Gallery.
    func position(at index: Int) -> String? {
        guard mode == .activity else { return nil }
        return MediaViewerMessages.position(index + 1, of: items.count)
    }

    /// `media_viewer_opened` (ADR-037 §13), for the Media it opens on.
    func openedEvent(source: AnalyticsEvent.MediaViewerSource, isOwn: Bool) -> AnalyticsEvent {
        .mediaViewerOpened(source: source, kind: items[start].media.kind, isOwn: isOwn)
    }
}
