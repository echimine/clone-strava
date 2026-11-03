import Foundation

/// The signed-in account as the Profile tab sees it: whose profile to load, and Réglages'
/// Nom and Email (ADR-036 §10). Built by the app shell from the session, so the Profile feature
/// does not depend on the Auth feature (ADR-007 rule 5).
struct ProfileAccount: Equatable, Sendable {
    let id: String
    /// The account name, until the profile is loaded.
    let name: String
    let email: String
}
