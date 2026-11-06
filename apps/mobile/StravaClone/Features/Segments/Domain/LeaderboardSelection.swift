import Foundation

/// The sex chip of a Leaderboard (ADR-039 §8): anything but Tous is Premium.
enum LeaderboardGender: String, CaseIterable, Sendable {
    case all, male, female
}

/// A calendar period in my time zone, the week from Monday.
enum LeaderboardPeriod: String, CaseIterable, Sendable {
    case today, week, month, year
}

/// The one other filter, combined with the sex chip (ADR-039 §8).
enum LeaderboardFilter: Hashable, Sendable {
    case period(LeaderboardPeriod)
    case following
    /// One of `ageBands`, from my current birth date.
    case age(String)
    /// One of `weightBands`, in kg, from my current weight.
    case weight(String)

    static let ageBands = ["0-19", "20-24", "25-34", "35-44", "45-54", "55-64", "65-69", "70-74", "75+"]
    static let weightBands = ["0-54", "55-64", "65-74", "75-84", "85-94", "95-104", "105-114", "115+"]

    /// `filter` and `value` of the query.
    var query: (filter: String, value: String?) {
        switch self {
        case .period(let period): ("period", period.rawValue)
        case .following: ("following", nil)
        case .age(let band): ("age", band)
        case .weight(let band): ("weight", band)
        }
    }

    var analytics: AnalyticsEvent.LeaderboardViewedFilter {
        switch self {
        case .period: .period
        case .following: .following
        case .age: .age
        case .weight: .weight
        }
    }
}

/// The chips of the Leaderboard screen (ADR-039 §15): a sex, and at most one other filter.
/// Tapping another chip replaces the filter; tapping the active one removes it.
struct LeaderboardSelection: Equatable, Sendable {
    var gender = LeaderboardGender.all
    var filter: LeaderboardFilter?

    /// Tous with no filter: the only Leaderboard without Premium (ADR-039 §9).
    var isFree: Bool { gender == .all && filter == nil }

    func tapping(_ tapped: LeaderboardGender) -> LeaderboardSelection {
        var next = self
        next.gender = tapped == gender ? .all : tapped
        return next
    }

    func tapping(_ tapped: LeaderboardFilter) -> LeaderboardSelection {
        var next = self
        next.filter = tapped == filter ? nil : tapped
        return next
    }

    /// `leaderboard_viewed {filter}`: the other filter when there is one, else the sex.
    var analytics: AnalyticsEvent.LeaderboardViewedFilter {
        if let filter { return filter.analytics }
        switch gender {
        case .all: return .all
        case .male: return .male
        case .female: return .female
        }
    }
}
