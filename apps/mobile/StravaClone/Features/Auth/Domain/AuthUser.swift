import Foundation

/// The signed-in user, as returned by Better Auth (ADR-022).
struct AuthUser: Equatable, Sendable, Codable {
    let id: String
    let email: String
    let name: String
}
