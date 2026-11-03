import Foundation

/// Another athlete's profile and its follow button (ADR-036 §1, §3, §10).
extension Di {
    /// A new one for each pushed profile: it lives as long as that screen.
    func makeAthleteProfileStore(athleteId: String) -> AthleteProfileStore {
        let athletes = APIAthleteRepository(apiClient: apiClient)
        return AthleteProfileStore(
            athleteId: athleteId,
            loadProfile: LoadAthleteProfile(repository: athletes),
            loadYearToDateDistance: LoadAthleteYearToDateDistance(repository: athletes),
            follows: makeFollowStore(),
            activities: AthleteActivitiesStore(
                loadActivities: LoadAthleteActivities(repository: athletes),
                setKudos: SetAthleteActivityKudos(repository: APIAthleteKudosRepository(apiClient: apiClient)),
                activityChanges: activityChanges
            )
        )
    }

    /// The follow buttons of one screen: a profile, a followers or following list, the search.
    func makeFollowStore() -> FollowStore {
        let follows = APIFollowRepository(apiClient: apiClient)
        return FollowStore(followAthlete: FollowAthlete(repository: follows), unfollowAthlete: UnfollowAthlete(repository: follows))
    }
}
