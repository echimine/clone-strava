import Foundation

/// What "Modifier le profil" shows and edits (ADR-036 §3), from `GET /v1/me/profile`. Empty texts
/// and nil values were never filled.
struct EditableProfile: Equatable, Sendable {
    static let bioMaxLength = 300
    static let cityMaxLength = 100
    static let weightKgRange = 20.0...300.0

    var firstName = ""
    var lastName = ""
    var bio = ""
    var city = ""
    /// ISO 3166-1 alpha-2 code, e.g. `FR`.
    var countryCode: String?
    /// The first Practiced sport.
    var mainSport: SportType?
    var birthDate: CalendarDay?
    var gender: Gender?
    var weightKg: Double?
}

/// An `EditableProfile` the server will accept, as `PATCH /v1/me/profile` sends it.
struct ProfileUpdate: Equatable, Sendable {
    enum Invalid: Error, Equatable {
        case name, bio, city, tooYoung, weight
    }

    let name: ProfileName
    /// Trimmed; empty clears it.
    let bio: String
    /// Trimmed; empty clears it.
    let city: String
    /// Empty clears it.
    let countryCode: String
    let mainSport: SportType?
    let birthDate: CalendarDay?
    let gender: Gender?
    let weightKg: Double?

    /// The age is checked on the UTC day, as the server does (ADR-035 §5).
    static func validate(_ profile: EditableProfile, today: CalendarDay = .utc(.now)) -> Result<ProfileUpdate, Invalid> {
        guard let name = ProfileName(firstName: profile.firstName, lastName: profile.lastName) else {
            return .failure(.name)
        }
        let bio = profile.bio.trimmingCharacters(in: .whitespacesAndNewlines)
        let city = profile.city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard bio.count <= EditableProfile.bioMaxLength else { return .failure(.bio) }
        guard city.count <= EditableProfile.cityMaxLength else { return .failure(.city) }
        if let birthDate = profile.birthDate, birthDate.years(until: today) < OnboardingAnswers.minimumAge {
            return .failure(.tooYoung)
        }
        if let weight = profile.weightKg, !EditableProfile.weightKgRange.contains(weight) {
            return .failure(.weight)
        }
        return .success(ProfileUpdate(
            name: name,
            bio: bio,
            city: city,
            countryCode: profile.countryCode ?? "",
            mainSport: profile.mainSport,
            birthDate: profile.birthDate,
            gender: profile.gender,
            weightKg: profile.weightKg
        ))
    }
}
