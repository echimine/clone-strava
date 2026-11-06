import Foundation

/// A rule of ADR-039 §5 a drawn path breaks, checked by the app and again by the server.
enum SegmentRuleViolation: String, Equatable, Sendable {
    case tooShort = "too_short"
    case tooLong = "too_long"
    case loop
}

extension SegmentSport {
    /// ADR-039 §5: 200 m on foot (run, walk, hike), 500 m by bike.
    var minimumLength: Distance {
        Distance(meters: self == .ride ? 500 : 200)
    }

    /// ADR-039 §5: 50 km at most, whatever the sport.
    static let maximumLength = Distance(meters: 50_000)
    /// ADR-039 §5: start and finish at least this far apart.
    static let minimumEndsApart = Distance(meters: 100)

    /// Every rule the path breaks, length first, as the server orders them.
    func violations(of path: [Coordinate]) -> [SegmentRuleViolation] {
        let length = zip(path, path.dropFirst()).reduce(Distance.zero) { $0 + $1.0.distance(to: $1.1) }
        var violations: [SegmentRuleViolation] = []
        if length.meters < minimumLength.meters - 0.01 {
            violations.append(.tooShort)
        }
        if length.meters > Self.maximumLength.meters + 0.01 {
            violations.append(.tooLong)
        }
        if let start = path.first, let finish = path.last, path.count >= 2,
           start.distance(to: finish).meters >= Self.minimumEndsApart.meters - 0.01 {
            return violations
        }
        violations.append(.loop)
        return violations
    }
}
