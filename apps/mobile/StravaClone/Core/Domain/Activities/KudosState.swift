import Foundation

/// Kudos of one activity as the server sees it after a give/remove (ADR-029). In Core because
/// the feed card and the Activity detail both give kudos (ADR-007 rule 5).
struct KudosState: Equatable, Sendable {
    let kudosCount: Int
    let viewerHasKudoed: Bool
}
