import Foundation

/// What an athlete can report (ADR-038 §9): another athlete's comment, Activity (as a whole,
/// Media included) or the athlete themself, or a Segment (ADR-039 §11). Never one's own content.
struct ReportTarget: Hashable, Sendable, Identifiable {
    enum Kind: String, Sendable {
        case comment, activity, athlete, segment
    }

    let kind: Kind
    /// The comment's, the Activity's or the athlete's id.
    let targetId: String
    /// Who wrote it (the athlete themself for `.athlete`): the one "Bloquer aussi" would block.
    /// None for a Segment, whose creator is never shown.
    let author: ActivityAuthor?

    var id: String { "\(kind.rawValue):\(targetId)" }

    static func comment(_ id: String, by author: ActivityAuthor) -> ReportTarget {
        ReportTarget(kind: .comment, targetId: id, author: author)
    }

    static func activity(_ id: ActivityID, by author: ActivityAuthor) -> ReportTarget {
        ReportTarget(kind: .activity, targetId: id.description, author: author)
    }

    static func athlete(_ athlete: ActivityAuthor) -> ReportTarget {
        ReportTarget(kind: .athlete, targetId: athlete.id, author: athlete)
    }

    /// « Signaler ce Segment »: it stays visible to the reporter (ADR-039 §11).
    static func segment(_ id: String) -> ReportTarget {
        ReportTarget(kind: .segment, targetId: id, author: nil)
    }
}

extension ActivityAuthor {
    /// "Bloquer aussi <prénom>": the first word of the name everyone sees.
    var firstName: String {
        displayName.split(separator: " ").first.map(String.init) ?? displayName
    }
}

extension AnalyticsEvent {
    /// Where "Bloquer" was confirmed (ADR-038 §8).
    enum BlockSource: String, Sendable {
        /// The "…" menu of an athlete's profile.
        case profile
        /// "Bloquer aussi <prénom>" after a Report.
        case reportConfirmation = "report_confirmation"
    }
}
