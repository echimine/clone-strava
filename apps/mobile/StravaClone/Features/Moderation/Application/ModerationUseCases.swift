import Foundation

/// "Envoyer" in the Report sheet (ADR-038 §9). The note is trimmed; a blank one is none.
struct ReportContent: Sendable {
    let repository: any ModerationRepository

    func callAsFunction(_ target: ReportTarget, reason: ReportReason, note: String) async throws(ModerationError) -> ReportOutcome {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await repository.report(target, reason: reason, note: trimmed.isEmpty ? nil : trimmed)
    }
}

/// "Bloquer" once confirmed (ADR-038 §8).
struct BlockAthlete: Sendable {
    let repository: any ModerationRepository

    func callAsFunction(_ athleteId: String) async throws(ModerationError) {
        try await repository.block(athleteId)
    }
}

/// "Débloquer" once confirmed, in Réglages > "Athlètes bloqués".
struct UnblockAthlete: Sendable {
    let repository: any ModerationRepository

    func callAsFunction(_ athleteId: String) async throws(ModerationError) {
        try await repository.unblock(athleteId)
    }
}

/// Réglages > "Athlètes bloqués".
struct LoadBlockedAthletes: Sendable {
    let repository: any ModerationRepository

    func callAsFunction() async throws(ModerationError) -> [BlockedAthlete] {
        try await repository.blockedAthletes()
    }
}
