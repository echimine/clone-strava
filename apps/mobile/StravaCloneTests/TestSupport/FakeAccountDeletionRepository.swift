import Foundation
@testable import StravaClone

/// In-memory `AccountDeletionRepository` (ADR-025 §3): scripted answers and recorded calls.
final class FakeAccountDeletionRepository: AccountDeletionRepository, @unchecked Sendable {
    enum Call: Equatable {
        case preview
        case sendCode
        case delete(code: String)
    }

    private let lock = NSLock()

    var previewResult: Result<Bool, AccountDeletionError> = .success(false)
    var sendCodeResult: Result<Void, AccountDeletionError> = .success(())
    var deleteResult: Result<Void, AccountDeletionError> = .success(())

    private(set) var calls: [Call] = []

    func appStoreBilled() async throws(AccountDeletionError) -> Bool {
        try lock.withLock {
            calls.append(.preview)
            return previewResult
        }.get()
    }

    func sendCode() async throws(AccountDeletionError) {
        try lock.withLock {
            calls.append(.sendCode)
            return sendCodeResult
        }.get()
    }

    func deleteAccount(code: String) async throws(AccountDeletionError) {
        try lock.withLock {
            calls.append(.delete(code: code))
            return deleteResult
        }.get()
    }
}
