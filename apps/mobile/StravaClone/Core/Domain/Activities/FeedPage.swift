import Foundation

/// One page of Activity cards (ADR-029): the feed, or an athlete's Activities, which the API
/// returns in the same format (ADR-036 §3). `nextCursor` is nil on the last page.
struct FeedPage: Equatable, Sendable {
    let posts: [ActivityPost]
    let nextCursor: String?
}
