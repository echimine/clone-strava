import Foundation

/// `user_profile.gender` (ADR-035 §4): `genderSchema` of the contract.
enum Gender: String, CaseIterable, Sendable {
    case male, female
    case nonBinary = "non_binary"
    case undisclosed
}

/// `user_profile.goals` (ADR-035 §4): `goalSchema` of the contract.
enum Goal: String, CaseIterable, Sendable {
    case compete
    case discoverRoutes = "discover_routes"
    case health
    case meetAthletes = "meet_athletes"
    case trainForEvent = "train_for_event"
    case buildHabit = "build_habit"
}

/// `user_profile.level` (ADR-035 §4): `athleteLevelSchema` of the contract.
enum AthleteLevel: String, CaseIterable, Sendable {
    case beginner, intermediate, advanced, professional
}

/// What a person entered during the Onboarding (ADR-035 §1), kept on the phone until the account
/// exists (§5). Raw values are those of `onboardingAnswersRequestSchema` in `packages/contracts`.
struct OnboardingAnswers: Equatable, Sendable {
    /// Nervo is for people aged 15 or more (ADR-035 §1).
    static let minimumAge = 15

    var firstName = ""
    var lastName = ""
    var birthDate: CalendarDay?
    var gender: Gender?
    /// The Practiced sports, in the order they were picked.
    var sports: [SportType] = []
    /// 0 to 6, in the order they were picked; empty when the question was skipped.
    var goals: [Goal] = []
    var level: AthleteLevel?

    /// Both names are required.
    var hasName: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A birth date is set and the person is old enough on `today`.
    func isOldEnough(on today: CalendarDay) -> Bool {
        guard let birthDate else { return false }
        return birthDate.years(until: today) >= Self.minimumAge
    }
}
