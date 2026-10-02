import Foundation

/// Sport of an activity, from the API's `sportTypeCode` (`sports.sport_type`, ADR-017).
/// Unknown codes are kept so new sports still display.
enum SportType: Hashable, Sendable {
    case run, ride, swim, walk, hike
    case other(String)

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
