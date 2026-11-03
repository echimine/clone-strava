import Foundation

extension ActivityAuthor {
    /// An athlete identity as every API response carries it, `{ id, displayName, avatarUrl }`
    /// (ADR-029 §2, ADR-036): one mapping for all the generated payload types.
    init(id: String, displayName: String, avatarUrl: String?) {
        self.init(id: id, displayName: displayName, avatarURL: avatarUrl.flatMap(URL.init(string:)))
    }
}
