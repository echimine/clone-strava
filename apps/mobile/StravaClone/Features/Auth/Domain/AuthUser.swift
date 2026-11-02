import Foundation

/// The signed-in user, as returned by Better Auth (ADR-022).
struct AuthUser: Equatable, Sendable, Codable {
    let id: String
    let email: String
    let name: String
    /// When the account was created, as the sign-in response tells it (ADR-035 §1).
    var createdAt: Date?

    init(id: String, email: String, name: String, createdAt: Date? = nil) {
        self.id = id
        self.email = email
        self.name = name
        self.createdAt = createdAt
    }

    /// The first word of `name`, as the Paywall greets the athlete; empty for an empty name.
    var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? ""
    }

    /// How recent an account must be for "Se connecter" to count as its creation (ADR-035 §1).
    static let newAccountWindow: TimeInterval = 2 * 60

    /// The sign-in that returned this user has just created the account: created less than
    /// `newAccountWindow` before `date`.
    func isNewAccount(at date: Date) -> Bool {
        guard let createdAt else { return false }
        return date.timeIntervalSince(createdAt) < Self.newAccountWindow
    }
}
