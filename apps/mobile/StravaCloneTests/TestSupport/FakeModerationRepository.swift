import Foundation
@testable import StravaClone

/// In-memory `ModerationRepository` (ADR-025 §3): scripted answers and recorded calls.
final class FakeModerationRepository: ModerationRepository, @unchecked Sendable {
    enum Call: Equatable {
        case report(ReportTarget, ReportReason, note: String?)
        case block(String)
        case unblock(String)
        case list
    }

    private let lock = NSLock()

    var reportResult: Result<ReportOutcome, ModerationError> = .success(.reported)
    var blockResult: Result<Void, ModerationError> = .success(())
    var unblockResult: Result<Void, ModerationError> = .success(())
    var listResult: Result<[BlockedAthlete], ModerationError> = .success([])

    private(set) var calls: [Call] = []

    func report(_ target: ReportTarget, reason: ReportReason, note: String?) async throws(ModerationError) -> ReportOutcome {
        try lock.withLock {
            calls.append(.report(target, reason, note: note))
            return reportResult
        }.get()
    }

    func block(_ athleteId: String) async throws(ModerationError) {
        try lock.withLock {
            calls.append(.block(athleteId))
            return blockResult
        }.get()
    }

    func unblock(_ athleteId: String) async throws(ModerationError) {
        try lock.withLock {
            calls.append(.unblock(athleteId))
            return unblockResult
        }.get()
    }

    func blockedAthletes() async throws(ModerationError) -> [BlockedAthlete] {
        try lock.withLock {
            calls.append(.list)
            return listResult
        }.get()
    }
}
