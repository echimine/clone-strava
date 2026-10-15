import Foundation

/// The French number formats of a Recording (ADR-031 §5, §9), the same on the Recording screen
/// and in the Live Activity: "12,34" km, "0,75" km left, "5:12" /km, "24,3" km/h. Values
/// without their unit. Compiled into the app and the widget extension (ADR-031 §15).
enum RecordingNumberFormat {
    static let dash = "–"
    static let locale = Locale(identifier: "fr_FR")

    /// "12,34" (km), truncated: never more than was covered.
    static func kilometers(_ meters: Double) -> String {
        let hundredths = Double(Int(max(0, meters) / 10)) / 100
        return hundredths.formatted(.number.precision(.fractionLength(2)).locale(locale))
    }

    /// "0,75" (km), rounded: a distance left is not a distance covered.
    static func remainingKilometers(_ meters: Double) -> String {
        (max(0, meters) / 1_000).formatted(.number.precision(.fractionLength(2)).locale(locale))
    }

    /// "5:12" (/km), or "–".
    static func pace(seconds: Int?) -> String {
        guard let seconds else { return dash }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// "24,3" (km/h), or "–".
    static func speed(kmh: Double?) -> String {
        guard let kmh else { return dash }
        return kmh.formatted(.number.precision(.fractionLength(1)).locale(locale))
    }
}
