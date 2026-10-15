import ActivityKit
import Foundation

/// The Live Activity of a Recording (ADR-031 §9, §15), compiled into the app (which starts and
/// updates it) and the widget extension (which draws it). Plain values only, about 300 bytes.
struct RecordingActivityAttributes: ActivityAttributes {
    /// Fixed at Start: "Course à pied".
    var sportName: String
    /// SF Symbol of the sport.
    var sportSymbol: String
    /// Average pace on foot, current speed on a bike.
    var showsPace: Bool

    struct ContentState: Codable, Hashable {
        /// Start moved forward by the finished Pauses: `Text(timerInterval:pauseTime:)` from
        /// here shows the time minus Pauses.
        var timerStart: Date
        /// Start of the Pause in progress, where the timer stops.
        var pausedAt: Date?
        var distanceM: Double
        /// Average pace in seconds per km, on foot.
        var averagePaceS: Int?
        /// `nil` during a Pause.
        var currentSpeedKmh: Double?
        var averageSpeedKmh: Double
        var itinerary: Itinerary?
        /// Final content after Save.
        var isSaved: Bool

        var isPaused: Bool { pausedAt != nil }
    }

    struct Itinerary: Codable, Hashable {
        var name: String
        /// `nil` before the first snap: "—".
        var remainingM: Double?
        /// Share of the track done, 0 to 1.
        var fraction: Double
        var state: ItineraryFollowState
    }
}
