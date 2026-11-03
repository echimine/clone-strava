import Foundation

/// French texts of the full-screen viewer (ADR-037 §10).
enum MediaViewerMessages {
    static let close = "Fermer"
    static let openActivity = "Voir l'activité"

    /// "3 sur 8".
    static func position(_ number: Int, of count: Int) -> String {
        "\(number) sur \(count)"
    }
}
