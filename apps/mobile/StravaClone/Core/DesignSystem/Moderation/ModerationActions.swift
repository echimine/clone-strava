import SwiftUI

/// What a Report hid for the viewer (ADR-038 §7).
enum ReportHiding: Equatable, Sendable {
    /// The reported comment or Activity, for good. Never sent for an athlete.
    case target
    /// Everything of its author, blocked from the Report's confirmation ("Bloquer aussi").
    case author
}

/// "Signaler" (ADR-038 §9), from any feature: the app shell presents the Report sheet. Features
/// know nothing of the Moderation feature (ADR-007 rule 5), only of this action.
/// `onHidden` runs each time something is hidden for the viewer: `.target` once the comment or
/// the Activity is reported, `.author` once its author is blocked from the confirmation.
struct ReportContentAction {
    let action: @MainActor (ReportTarget, @escaping @MainActor (ReportHiding) -> Void) -> Void

    @MainActor func callAsFunction(_ target: ReportTarget, onHidden: @escaping @MainActor (ReportHiding) -> Void = { _ in }) {
        action(target, onHidden)
    }
}

/// "Bloquer" (ADR-038 §8) from an athlete's profile: the app shell asks for the confirmation,
/// then blocks. `onBlocked` runs once the Block is recorded.
struct BlockAthleteAction {
    let action: @MainActor (ActivityAuthor, @escaping @MainActor () -> Void) -> Void

    @MainActor func callAsFunction(_ athlete: ActivityAuthor, onBlocked: @escaping @MainActor () -> Void = {}) {
        action(athlete, onBlocked)
    }
}

/// The menu items every feature shows for these actions.
enum ModerationLabels {
    static let report = "Signaler"
    static let reportImage = "flag"
    static let block = "Bloquer"
    static let blockImage = "hand.raised"
}

extension EnvironmentValues {
    /// Nil where nothing can be reported (previews): "Signaler" is then not offered.
    @Entry var reportContent: ReportContentAction?
    /// Nil where nobody can be blocked (previews): "Bloquer" is then not offered.
    @Entry var blockAthlete: BlockAthleteAction?
}
