import Foundation

/// The fixed reasons of a Report (ADR-038 §9).
enum ReportReason: String, CaseIterable, Sendable {
    case spam
    case harassment
    case sexualOrViolent = "sexual_or_violent"
    /// An athlete only.
    case impersonation
    /// The note is required.
    case other

    /// The reasons offered for this kind of target, in the sheet's order.
    static func choices(for kind: ReportTarget.Kind) -> [ReportReason] {
        allCases.filter { $0 != .impersonation || kind == .athlete }
    }

    var requiresNote: Bool { self == .other }
}

/// What the server made of a Report.
enum ReportOutcome: Equatable, Sendable {
    /// A new Report (`201`).
    case reported
    /// This athlete already has a Report in the target's open case (`200`): "Déjà signalé".
    case alreadyReported
}

/// One athlete of Réglages > "Athlètes bloqués".
struct BlockedAthlete: Hashable, Sendable, Identifiable {
    let athlete: ActivityAuthor
    let blockedAt: Date

    var id: String { athlete.id }
}

enum ModerationError: Error, Equatable, Sendable {
    case offline
    case network
    case unauthorized
    /// The target no longer exists or is no longer visible (`404`).
    case notFound
    /// More than 20 Reports in 24 hours (`429`).
    case rateLimited
    /// Any other server answer, with its machine-readable code when there is one.
    case server(code: String?)
}

/// Reports and Blocks (ADR-038 §8, §9), online only. Implemented over the API in
/// `Infrastructure`, faked in tests.
protocol ModerationRepository: Sendable {
    func report(_ target: ReportTarget, reason: ReportReason, note: String?) async throws(ModerationError) -> ReportOutcome
    /// Idempotent.
    func block(_ athleteId: String) async throws(ModerationError)
    /// Idempotent.
    func unblock(_ athleteId: String) async throws(ModerationError)
    /// Those the viewer blocked, most recent first.
    func blockedAthletes() async throws(ModerationError) -> [BlockedAthlete]
}

/// At most this many characters in a Report's note.
let reportNoteMaxLength = 500
