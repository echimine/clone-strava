import Foundation

/// French texts of the activity card (ADR-036 §5).
enum ActivityCardMessages {
    static let distance = "Distance"
    static let pace = "Allure"
    static let elevation = "Dénivelé"
    static let time = "Temps"
    static let routeTrimmed = "Départ et arrivée masqués"

    /// "N ont envoyé des kudos · N commentaires", each part hidden at zero; nil when both are.
    static func socialSummary(kudosCount: Int, commentCount: Int) -> String? {
        var parts: [String] = []
        if kudosCount > 0 {
            parts.append("\(number(kudosCount)) \(kudosCount == 1 ? "a" : "ont") envoyé des kudos")
        }
        if commentCount > 0 {
            parts.append("\(number(commentCount)) \(commentCount == 1 ? "commentaire" : "commentaires")")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func number(_ value: Int) -> String {
        value.formatted(.number.locale(ActivityFormatters.locale))
    }
}
