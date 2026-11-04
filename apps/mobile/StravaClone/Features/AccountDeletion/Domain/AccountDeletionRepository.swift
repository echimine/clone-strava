import Foundation

enum AccountDeletionError: Error, Equatable, Sendable {
    case offline
    case network
    case unauthorized
    /// `403 admin_cannot_delete_account`: an Administrator cannot delete their account.
    case administrator
    /// `400 invalid_code`: not the code sent.
    case invalidCode
    /// `400 code_expired` / `too_many_attempts`: a new code is needed.
    case expiredCode
    /// Any other server answer.
    case server
}

/// « Supprimer mon compte » (ADR-038 §13), online only: a Sign-in code sent to the account's
/// e-mail re-verifies the athlete, then the deletion is immediate and final. Implemented over
/// the API in `Infrastructure`, faked in tests.
protocol AccountDeletionRepository: Sendable {
    /// Whether an App Store subscription keeps being billed, which the deletion does not stop.
    func appStoreBilled() async throws(AccountDeletionError) -> Bool
    /// Sends the Sign-in code to the account's address.
    func sendCode() async throws(AccountDeletionError)
    /// Deletes the account once `code` checks out.
    func deleteAccount(code: String) async throws(AccountDeletionError)
}
