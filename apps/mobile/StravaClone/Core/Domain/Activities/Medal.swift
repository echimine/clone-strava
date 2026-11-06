import Foundation

/// A Medal (ADR-039 §8): the athlete's 1st, 2nd or 3rd time at the date of the Activity, on a
/// Best effort or a Segment. Drawn by `MedalRibbon`.
enum Medal: String, CaseIterable, Hashable, Sendable {
    case gold, silver, bronze
}
