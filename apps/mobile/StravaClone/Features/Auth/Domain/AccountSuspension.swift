import Foundation

/// A banned athlete's account, as the sign-in refusal tells it (ADR-038 §6: `403 BANNED_USER`):
/// what « Compte suspendu » shows.
struct AccountSuspension: Equatable, Sendable {
    /// End of the Ban; `nil` for a permanent one (« définitivement »).
    let until: Date?
    /// The reason the Administrator typed.
    let reason: String?
    /// The team's address to contest it; `nil` when the server has none configured.
    let contactEmail: String?
}
