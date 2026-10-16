import Foundation

/// Sport of an activity, from the API's `sportTypeCode` (`sports.sport_type`, ADR-017).
/// Unknown codes are kept so new sports still display.
enum SportType: Hashable, Sendable {
    case run, ride, swim, walk, hike
    case other(String)

    /// How a sport's speed is shown (`sports.pace_unit`, ADR-017).
    enum PaceUnit: Sendable {
        /// Minutes per kilometer.
        case pace
        /// Kilometers per hour.
        case speed
    }

    init(code: String) {
        switch code {
        case "run": self = .run
        case "ride": self = .ride
        case "swim": self = .swim
        case "walk": self = .walk
        case "hike": self = .hike
        default: self = .other(code)
        }
    }

    /// `sport_type.tracks_distance` (seed `0002_seed_sport_types`); the column default for
    /// unknown sports.
    var tracksDistance: Bool { true }

    /// `sport_type.tracks_elevation`: not in the water.
    var tracksElevation: Bool { self != .swim }

    /// `sport_type.pace_unit`: speed on a bike, pace otherwise.
    var paceUnit: PaceUnit { self == .ride ? .speed : .pace }

    var code: String {
        switch self {
        case .run: "run"
        case .ride: "ride"
        case .swim: "swim"
        case .walk: "walk"
        case .hike: "hike"
        case .other(let code): code
        }
    }
}
