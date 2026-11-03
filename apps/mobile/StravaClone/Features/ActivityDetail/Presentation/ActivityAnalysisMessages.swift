import Foundation

/// French strings of the detail's map, source and analysis sections (ADR-036 §9).
enum ActivityAnalysisMessages {
    // MARK: Map

    static let openMap = "Agrandir la carte"
    static let closeMap = "Fermer"
    static let recentre = "Recentrer sur le tracé"

    // MARK: Source

    static func source(_ source: ActivitySource) -> String {
        switch source {
        case .recorded: "Enregistré avec Nervo"
        // The API does not say the file format (FIT, GPX or TCX) yet.
        case .imported: "Importé"
        case .manual: "Saisie manuelle"
        }
    }

    // MARK: Splits

    static let splitsTitle = "Temps intermédiaires"
    static let kilometre = "Km"
    static let pace = "Allure"
    static let speed = "Vitesse"
    static let elevation = "Élév."
    static let heartRate = "FC"

    // MARK: Pace and speed

    static func averageSpeed(pace: Bool) -> String { pace ? "Allure moyenne" : "Vitesse moyenne" }
    static func elapsedSpeed(pace: Bool) -> String { pace ? "Allure sur le temps écoulé" : "Vitesse sur le temps écoulé" }
    static let elapsedTime = "Temps écoulé"
    static let fastestSplit = "Split le plus rapide"

    // MARK: Heart rate

    static let heartRateTitle = "Fréquence cardiaque"
    static let averageHeartRate = "FC moyenne"
    static let maxHeartRate = "FC max"

    static func bpm(_ value: Int) -> String { "\(value) bpm" }

    static func distanceAxis(_ kilometers: Double) -> String {
        "\(kilometers.formatted(.number.precision(.fractionLength(0...1)).locale(ActivityFormatters.locale))) km"
    }
}
