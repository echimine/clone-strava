import Foundation

/// A Segment's sport: one of the sports with a map (ADR-039 §5), in the order of the Map chips.
enum SegmentSport: String, CaseIterable, Sendable {
    case ride, run, walk, hike

    var sportType: SportType {
        switch self {
        case .ride: .ride
        case .run: .run
        case .walk: .walk
        case .hike: .hike
        }
    }
}

/// Climb category from the length × grade rule (ADR-039 §5); none under a score of 8,000.
enum ClimbCategory: String, Sendable {
    case hc
    case cat1 = "1"
    case cat2 = "2"
    case cat3 = "3"
    case cat4 = "4"

    /// « HC », « Cat. 1 » … « Cat. 4 ».
    var label: String {
        self == .hc ? "HC" : "Cat. \(rawValue)"
    }
}
