import Foundation

/// Opens an athlete's profile in the current tab's stack (ADR-036 §10). In Core because the
/// feed, a detail, the Kudos and comments lists and the profiles all open it; each tab's
/// `NavigationStack` registers it.
struct AthleteProfileRequest: Hashable, Sendable {
    let id: String

    /// Where a tap on an athlete leads.
    enum Destination: Equatable {
        /// The viewer themself: the Profile tab.
        case ownProfile
        case push(AthleteProfileRequest)
    }

    static func destination(of athleteId: String, viewerId: String?) -> Destination {
        athleteId == viewerId ? .ownProfile : .push(AthleteProfileRequest(id: athleteId))
    }
}
