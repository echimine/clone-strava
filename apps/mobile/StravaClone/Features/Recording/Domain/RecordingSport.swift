import Foundation

/// Sports a Recording can be made for (ADR-031 §1): the sports with GPS. Fixed after Start.
enum RecordingSport: String, CaseIterable, Codable, Sendable {
    case run, ride, walk, hike

    var sportType: SportType {
        SportType(code: rawValue)
    }

    /// Pace on foot, speed on a bike (ADR-031 §5).
    var isOnFoot: Bool {
        self != .ride
    }

    /// Plausible top speed of the server's cleanup (`maxPlausibleSpeedMs`, ADR-019 §5 step 3).
    var maxPlausibleSpeedMs: Double {
        switch self {
        case .run: 12
        case .ride: 35
        case .walk, .hike: 5
        }
    }

    /// `sports.min_duration_s` (ADR-031 §11): shorter, the Activity cannot be saved.
    var minimumDuration: Duration {
        self == .hike ? .seconds(300) : .seconds(60)
    }
}
