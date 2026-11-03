import Foundation

/// French strings of the Kudos and comments screen (ADR-036 §8).
enum ActivityEngagementMessages {
    static let tabs = "Kudos ou commentaires"
    static let noKudos = "Aucun kudos pour l'instant"

    /// "Kudos · 4"; "Kudos" until the Activity is loaded.
    static func kudosTab(_ count: Int?) -> String {
        segment("Kudos", count)
    }

    /// "Commentaires · 2"; "Commentaires" until the Activity is loaded.
    static func commentsTab(_ count: Int?) -> String {
        segment(ActivityCommentMessages.title, count)
    }

    /// The detail's comment button.
    static func commentsButton(_ count: Int) -> String {
        count == 1 ? "1 commentaire" : "\(count.formatted()) commentaires"
    }

    private static func segment(_ title: String, _ count: Int?) -> String {
        count.map { "\(title) · \($0.formatted())" } ?? title
    }
}
