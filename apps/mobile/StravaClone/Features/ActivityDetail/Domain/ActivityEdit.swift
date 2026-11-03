import Foundation

/// What the athlete can change on a processed Activity (`PATCH /v1/activities/:id`, ADR-033 §4).
struct ActivityEdit: Hashable, Sendable {
    let title: String
    /// Nil clears the description.
    let description: String?
    let sport: SportType
    let visibility: ActivityVisibility
    /// The full Media order (ADR-037 §8), Media still being sent included: sent when the Media
    /// changed (added, removed, reordered), so the server's positions are the indexes the Media
    /// still being sent confirm with.
    var mediaOrder: [UUID]? = nil
    /// The first Media goes before the map; sent with `mediaOrder`.
    var mediaFirst: Bool? = nil

    /// The optimistic detail (ADR-033 §7): the official values stay until the server
    /// recomputes them for a new sport (§5). Its Media follow `mediaOrder`, those left out
    /// (removed) go; the Media still being sent come from the board.
    func applied(to detail: ActivityDetail) -> ActivityDetail {
        var edited = detail
        edited.title = title
        edited.description = description
        edited.sport = sport
        edited.visibility = visibility
        if let mediaOrder {
            edited.media = mediaOrder.compactMap { id in detail.media.first { $0.id == id } }
        }
        if let mediaFirst {
            edited.mediaFirst = mediaFirst
        }
        return edited
    }
}
