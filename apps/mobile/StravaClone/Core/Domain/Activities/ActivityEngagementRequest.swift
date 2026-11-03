import Foundation

/// Opening of an Activity's Kudos and comments screen (ADR-036 §8): the navigation value pushed
/// from the detail's kudos row and comment button, and from the card's comment button, and what
/// the app shell's `openEngagement` builds the screen from.
struct ActivityEngagementRequest: Hashable, Sendable {
    /// The segment shown first.
    enum Tab: Hashable, Sendable {
        case kudos
        case comments
    }

    let activityId: ActivityID
    var tab: Tab
    /// The comment buttons: the screen opens with the keyboard on the composer.
    var focusComposer = false

    /// The detail's kudos row.
    static func kudos(_ activityId: ActivityID) -> ActivityEngagementRequest {
        ActivityEngagementRequest(activityId: activityId, tab: .kudos)
    }

    /// The comment button of the card or the detail: Commentaires, composer focused.
    static func comments(_ activityId: ActivityID) -> ActivityEngagementRequest {
        ActivityEngagementRequest(activityId: activityId, tab: .comments, focusComposer: true)
    }
}
