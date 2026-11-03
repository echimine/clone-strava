import Foundation

/// The name "Modifier le profil" sends (ADR-036 §3): first and last name, each trimmed and 1 to
/// 50 characters, as `PATCH /v1/me/profile` requires.
struct ProfileName: Equatable, Sendable {
    static let maxLength = 50

    let firstName: String
    let lastName: String

    /// Nil when either part is empty or too long once trimmed.
    init?(firstName: String, lastName: String) {
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...Self.maxLength).contains(first.count), (1...Self.maxLength).contains(last.count) else { return nil }
        self.firstName = first
        self.lastName = last
    }

    /// "Prénom Nom", as the server shows it.
    var displayName: String { "\(firstName) \(lastName)" }

    /// The fields the sheet starts from: the shown name's first word, then the rest.
    static func parts(of displayName: String) -> (firstName: String, lastName: String) {
        let words = displayName.split(separator: " ", maxSplits: 1)
        return (words.first.map(String.init) ?? "", words.dropFirst().first.map(String.init) ?? "")
    }
}
