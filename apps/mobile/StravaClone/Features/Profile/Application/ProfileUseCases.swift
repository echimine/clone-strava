import Foundation

/// The profile's header, counters and own-only settings (ADR-036 §3).
struct LoadProfile: Sendable {
    let repository: any AthleteRepository

    func callAsFunction(athleteId: String) async throws(AthleteError) -> AthleteProfile {
        try await repository.profile(of: athleteId)
    }
}

/// One page of the profile's Activités tab (ADR-036 §3).
struct LoadProfileActivities: Sendable {
    let repository: any AthleteRepository

    func callAsFunction(athleteId: String, cursor: String? = nil) async throws(AthleteError) -> FeedPage {
        try await repository.activities(of: athleteId, cursor: cursor)
    }
}

/// Plus's "Statistiques — Cette année : X km" (ADR-036 §4).
struct LoadYearToDateDistance: Sendable {
    let repository: any AthleteRepository

    func callAsFunction(athleteId: String) async throws(AthleteError) -> Distance {
        try await repository.yearToDateDistance(of: athleteId)
    }
}

/// "Modifier le profil" (ADR-036 §3).
struct RenameAthlete: Sendable {
    let repository: any ProfileRepository

    func callAsFunction(_ name: ProfileName) async throws(AthleteError) -> ActivityAuthor {
        try await repository.rename(name)
    }
}

/// "Approuver mes abonnés" (ADR-036 §1).
struct SetApproveFollowers: Sendable {
    let repository: any ProfileRepository

    func callAsFunction(_ approve: Bool) async throws(AthleteError) -> Bool {
        try await repository.setApproveFollowers(approve)
    }
}
