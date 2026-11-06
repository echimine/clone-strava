import Foundation

/// Why a Segments call failed (ADR-039 §12), whichever screen made it: the Map, the creation,
/// a sheet and its Leaderboard, or Plus › « Segments ». Each screen shows the cases it can meet.
enum SegmentError: Error, Equatable, Sendable {
    case offline
    case unauthorized
    /// Deleted: « Ce Segment n'est plus disponible ».
    case notFound
    /// A filter, a sex or a page without Premium (ADR-039 §9).
    case premiumRequired
    /// « Supprimer » refused: someone else has an Effort on it (ADR-039 §5).
    case hasOtherEfforts
    /// The Map's zone is larger than a screen at zoom 10.5 (`400 zone_too_large`).
    case zoneTooLarge
    /// `409 duplicate`: an existing Segment of the same sport matches it both ways.
    case duplicate(SegmentRef)
    /// `429 quota`: 10 Segments created over the rolling 24 h.
    case quota
    /// `422`: the rules of ADR-039 §5 the server checked again.
    case rejected([SegmentRuleViolation])
    /// Any other refusal (an invalid name, a cursor…), with its code.
    case invalid(code: String?)
    /// Server failure (an `ElevationService` down included), or an answer the app cannot read:
    /// worth retrying.
    case server
    case network
}
