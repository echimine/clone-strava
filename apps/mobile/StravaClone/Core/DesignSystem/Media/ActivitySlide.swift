import Foundation

/// One slide of an Activity's carousel (ADR-037 §7, §10): its map or one of its Media.
/// Generic over the Media so the author's local Media (still being sent) compose the same way.
enum ActivitySlide<Media: Identifiable & Hashable>: Identifiable, Hashable {
    case map
    case media(Media)

    enum ID: Hashable {
        case map
        case media(Media.ID)
    }

    var id: ID {
        switch self {
        case .map: .map
        case .media(let media): .media(media.id)
        }
    }

    /// The slides in display order (ADR-037 §8): the map, then the Media; with `mediaFirst`,
    /// the first Media, the map, then the rest. Without a map the carousel starts with the
    /// first Media, so `mediaFirst` only matters with both a map and Media.
    static func compose(hasMap: Bool, media: [Media], mediaFirst: Bool) -> [ActivitySlide] {
        let mediaSlides = media.map(ActivitySlide.media)
        guard hasMap else { return mediaSlides }
        guard mediaFirst, let first = mediaSlides.first else { return [.map] + mediaSlides }
        return [first, .map] + mediaSlides.dropFirst()
    }
}

extension ActivityPost {
    /// The card's carousel: the route map when there is one, and the Media.
    var slides: [ActivitySlide<ActivityMedia>] {
        ActivitySlide.compose(hasMap: route != nil, media: media, mediaFirst: mediaFirst)
    }

    /// The same, with the author's Media still being sent (ADR-037 §5) at their place.
    @MainActor
    func slides(merging uploads: MediaUploadBoard?) -> [ActivitySlide<ActivityMedia>] {
        let media = uploads?.media(of: id, merging: media) ?? media
        return ActivitySlide.compose(hasMap: route != nil, media: media, mediaFirst: mediaFirst)
    }
}
