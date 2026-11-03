import Foundation

/// Another athlete's header, counters and follow status (ADR-036 §3).
struct LoadAthleteProfile: Sendable {
    let repository: any AthleteRepository

    func callAsFunction(athleteId: String) async throws(AthleteError) -> AthleteProfile {
        try await repository.profile(of: athleteId)
    }
}

/// One page of their Activités tab: only what the viewer may see (ADR-036 §3).
struct LoadAthleteActivities: Sendable {
    let repository: any AthleteRepository

    func callAsFunction(athleteId: String, cursor: String? = nil) async throws(AthleteError) -> FeedPage {
        try await repository.activities(of: athleteId, cursor: cursor)
    }
}

/// Plus's "Statistiques — Cette année : X km" (ADR-036 §4).
struct LoadAthleteYearToDateDistance: Sendable {
    let repository: any AthleteRepository

    func callAsFunction(athleteId: String) async throws(AthleteError) -> Distance {
        try await repository.yearToDateDistance(of: athleteId)
    }
}

/// The kudos button of a card on their profile (ADR-029).
struct SetAthleteActivityKudos: Sendable {
    let repository: any AthleteKudosRepository

    func callAsFunction(_ given: Bool, activityId: ActivityID) async throws(AthleteError) -> KudosState {
        try await repository.setKudos(given, activityId: activityId)
    }
}

/// "Suivre" (ADR-036 §1): follows, or asks to.
struct FollowAthlete: Sendable {
    let repository: any FollowRepository

    func callAsFunction(_ athleteId: String) async throws(AthleteError) -> FollowChange {
        try await repository.follow(athleteId)
    }
}

/// A page of an athlete's followers or following (ADR-036 §1).
struct LoadFollowList: Sendable {
    let repository: any FollowListRepository

    func callAsFunction(_ list: AthleteFollowsRequest.List, of athleteId: String, cursor: String? = nil) async throws(AthleteError) -> AthleteListPage {
        try await repository.list(list, of: athleteId, cursor: cursor)
    }
}

/// A page of "Demandes d'abonnement" (ADR-036 §1).
struct LoadFollowRequests: Sendable {
    let repository: any FollowListRepository

    func callAsFunction(cursor: String? = nil) async throws(AthleteError) -> FollowRequestPage {
        try await repository.followRequests(cursor: cursor)
    }
}

/// "Accepter" on a follow request.
struct AcceptFollowRequest: Sendable {
    let repository: any FollowListRepository

    func callAsFunction(from followerId: String) async throws(AthleteError) {
        try await repository.acceptRequest(from: followerId)
    }
}

/// "Refuser" on a follow request.
struct RefuseFollowRequest: Sendable {
    let repository: any FollowListRepository

    func callAsFunction(from followerId: String) async throws(AthleteError) {
        try await repository.refuseRequest(from: followerId)
    }
}

/// "Retirer" on one of the viewer's followers (ADR-036 §1).
struct RemoveFollower: Sendable {
    let repository: any FollowListRepository

    func callAsFunction(_ followerId: String) async throws(AthleteError) {
        try await repository.removeFollower(followerId)
    }
}

/// The search behind the profile's magnifier (ADR-036 §2).
struct SearchAthletes: Sendable {
    let repository: any AthleteSearchRepository

    func callAsFunction(_ query: String) async throws(AthleteError) -> [AthleteListItem] {
        try await repository.search(query)
    }
}

/// "Se désabonner", or a tap on "Demande envoyée" (ADR-036 §1).
struct UnfollowAthlete: Sendable {
    let repository: any FollowRepository

    func callAsFunction(_ athleteId: String) async throws(AthleteError) -> FollowChange {
        try await repository.unfollow(athleteId)
    }
}
