import Foundation

/// What the athlete can change on a processed Activity (`PATCH /v1/activities/:id`, ADR-033 §4).
struct ActivityEdit: Hashable, Sendable {
    let title: String
    /// Nil clears the description.
    let description: String?
    let sport: SportType
    let visibility: ActivityVisibility
    /// The full Media order (ADR-037 §8), Media still being sent included: sent when Media were
    /// added, so the server's positions are the indexes the new Media confirm with.
    var mediaOrder: [UUID]? = nil

    /// The optimistic detail (ADR-033 §7): the official values stay until the server
    /// recomputes them for a new sport (§5).
    func applied(to detail: ActivityDetail) -> ActivityDetail {
        var edited = detail
        edited.title = title
        edited.description = description
        edited.sport = sport
        edited.visibility = visibility
        return edited
    }
}
