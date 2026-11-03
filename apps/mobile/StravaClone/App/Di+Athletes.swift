import Foundation

/// Another athlete's profile, the follow button, the followers and following lists and the
/// search (ADR-036 §1, §2, §3, §10).
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
    /// What they change moves my own following counter on the Profile tab.
    func makeFollowStore() -> FollowStore {
        let follows = APIFollowRepository(apiClient: apiClient)
        let store = FollowStore(followAthlete: FollowAthlete(repository: follows), unfollowAthlete: UnfollowAthlete(repository: follows))
        let profile = makeProfileStore()
        store.observeChanges { previous, change in
            profile.apply(.following(from: previous, to: change.status))
        }
        return store
    }

    /// A new one for each pushed followers and following lists (ADR-036 §1). On my own, what
    /// it changes moves my Profile tab's counters.
    func makeFollowListStore(request: AthleteFollowsRequest) -> FollowListStore {
        let lists = APIFollowListRepository(apiClient: apiClient)
        let profile = makeProfileStore()
        return FollowListStore(
            request: request,
            loadList: LoadFollowList(repository: lists),
            removeFollower: RemoveFollower(repository: lists),
            follows: makeFollowStore(),
            requests: FollowRequestsStore(
                loadRequests: LoadFollowRequests(repository: lists),
                acceptRequest: AcceptFollowRequest(repository: lists),
                refuseRequest: RefuseFollowRequest(repository: lists)
            ),
            ownCountsChanged: { profile.apply($0) }
        )
    }

    /// A new one for each pushed search (ADR-036 §2).
    func makeAthleteSearchStore() -> AthleteSearchStore {
        AthleteSearchStore(
            searchAthletes: SearchAthletes(repository: APIAthleteSearchRepository(apiClient: apiClient)),
            follows: makeFollowStore()
        )
    }
}
