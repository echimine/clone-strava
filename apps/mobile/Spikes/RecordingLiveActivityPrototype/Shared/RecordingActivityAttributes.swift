// PROTOTYPE — throwaway (wayfinder #43, ticket #53 « Live Activity d'une Recording : contenu, boutons et fin de vie »).
// Lives only on the `prototype/recording-live-activity` branch, never merged.
// Compiled in both the app and the widget extension.

import ActivityKit
import AppIntents
import Foundation
import SwiftUI

enum ProtoSport: String, Codable, CaseIterable, Identifiable {
    case run, ride, walk, hike
    var id: Self { self }

    var label: String {
        switch self {
        case .run: "Course à pied"
        case .ride: "Vélo"
        case .walk: "Marche"
        case .hike: "Randonnée"
        }
    }

    var symbol: String {
        switch self {
        case .run: "figure.run"
        case .ride: "figure.outdoor.cycle"
        case .walk: "figure.walk"
        case .hike: "figure.hiking"
        }
    }

    var isOnFoot: Bool { self != .ride }

    var metersPerSecond: Double {
        switch self {
        case .run: 3.0
        case .ride: 7.0
        case .walk: 1.4
        case .hike: 1.1
        }
    }
}

enum ItineraryStatus: String, Codable, CaseIterable, Identifiable {
    case notYetSnapped, onTrack, offTrack, rerouted, finished
    var id: Self { self }

    var label: String {
        switch self {
        case .notYetSnapped: "Pas encore accroché (—)"
        case .onTrack: "Sur le tracé"
        case .offTrack: "Hors Itinéraire"
        case .rerouted: "Chemin recalculé"
        case .finished: "Itinéraire terminé"
        }
    }
}

enum ProtoVariant: String, Codable, CaseIterable, Identifiable {
    case A, B, C
    var id: Self { self }

    var name: String {
        switch self {
        case .A: "Façon Strava, sans bouton"
        case .B: "Miroir de l'écran + bouton Pause"
        case .C: "Itinéraire d'abord"
        }
    }
}

struct RecordingActivityAttributes: ActivityAttributes {
    /// Frozen at start (« Parcours de démarrage d'une Recording »).
    var sport: ProtoSport

    struct ContentState: Codable, Hashable {
        var variant: ProtoVariant
        /// Chrono start, pushed forward on each resume: the chrono excludes Pauses.
        var chronoStart: Date
        var pausedAt: Date?
        var distanceMeters: Double
        var avgPaceSecondsPerKm: Double?
        var currentSpeedKmh: Double?
        var avgSpeedKmh: Double?
        var itinerary: ItineraryProgress?
        var ending: Ending?

        var isPaused: Bool { pausedAt != nil }
    }

    struct ItineraryProgress: Codable, Hashable {
        var name: String
        var totalMeters: Double
        var remainingMeters: Double
        var status: ItineraryStatus

        var fraction: Double {
            guard totalMeters > 0, status != .notYetSnapped else { return 0 }
            return min(1, max(0, 1 - remainingMeters / totalMeters))
        }
    }

    /// Final content shown once the Recording is saved.
    struct Ending: Codable, Hashable {
        var movingSeconds: Int
    }
}

/// The only Live Activity control prototyped (variant B). Runs in the app's process.
struct TogglePauseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause / reprise de la Recording"

    func perform() async throws -> some IntentResult {
        #if APP
        await MainActor.run { RecordingSimulation.shared.togglePause(from: "Live Activity") }
        #endif
        return .result()
    }
}

enum Fmt {
    static let accent = Color(red: 0.99, green: 0.32, blue: 0.0)
    static let pause = Color.yellow

    static func km(_ meters: Double) -> String {
        (meters / 1000).formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "fr_FR")))
    }

    static func kmShort(_ meters: Double) -> String {
        (meters / 1000).formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "fr_FR")))
    }

    static func pace(_ secondsPerKm: Double?) -> String {
        guard let s = secondsPerKm, s.isFinite, s > 0, s < 3600 else { return "–:––" }
        let total = Int(s.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func speed(_ kmh: Double?) -> String {
        guard let kmh, kmh.isFinite else { return "–" }
        return kmh.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "fr_FR")))
    }

    static func duration(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
