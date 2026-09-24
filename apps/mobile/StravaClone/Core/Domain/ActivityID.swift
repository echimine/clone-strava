import Foundation

/// Activity identifier, generated on the phone when recording starts so that
/// API calls can be replayed without creating duplicates (ADR-008 §4).
struct ActivityID: Hashable, Codable, Sendable, CustomStringConvertible {
    let rawValue: UUID

    init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    var description: String { rawValue.uuidString.lowercased() }
}
