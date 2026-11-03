import Foundation

/// An athlete in a followers or following list, a follow request or a search result (ADR-036
/// §1, §2), with the viewer's follow button.
struct AthleteListItem: Equatable, Sendable, Identifiable {
    let athlete: ActivityAuthor
    /// Nil for the viewer themself: no button.
    let viewerFollowStatus: FollowStatus?

    var id: String { athlete.id }
}

/// Finds athletes by name (ADR-036 §2). Implemented over the API in `Infrastructure`, faked in
/// tests.
protocol AthleteSearchRepository: Sendable {
    /// At most 20 athletes whose first name, last name or full name contains `query`, ignoring
    /// case and accents; never the viewer.
    func search(_ query: String) async throws(AthleteError) -> [AthleteListItem]
}
