import Foundation

/// Opening of an Activity's detail (ADR-033 §1): the navigation value a list pushes, and what
/// the app shell's `openActivity` builds the detail from.
struct ActivityDetailRequest: Hashable, Sendable {
    let id: ActivityID
    /// From the card's comment button: the detail scrolls to the comments with the composer
    /// focused (ADR-034).
    var showsComments = false
}
