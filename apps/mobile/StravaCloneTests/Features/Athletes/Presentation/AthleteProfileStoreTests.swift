import Foundation
import Testing
@testable import StravaClone

@MainActor
struct AthleteProfileStoreTests {
    private func makeStore(
        _ athletes: FakeAthleteRepository,
        _ follows: FakeFollowRepository = FakeFollowRepository()
    ) -> AthleteProfileStore {
        AthleteProfileStore(
            athleteId: "lea",
            loadProfile: LoadAthleteProfile(repository: athletes),
            loadYearToDateDistance: LoadAthleteYearToDateDistance(repository: FakeAthleteStatsRepository.allSports()),
            follows: FollowStore(followAthlete: FollowAthlete(repository: follows), unfollowAthlete: UnfollowAthlete(repository: follows)),
            activities: AthleteActivitiesStore(
                loadActivities: LoadAthleteActivities(repository: athletes),
                setKudos: SetAthleteActivityKudos(repository: FakeAthleteKudosRepository())
            )
        )
    }

    private func repository(status: FollowStatus, followers: Int = 10) -> FakeAthleteRepository {
        let athletes = FakeAthleteRepository()
        athletes.profileResult = .success(.lea(status: status, followers: followers))
        athletes.pages[nil] = .success(FeedPage(posts: [.fixture()], nextCursor: nil))
        return athletes
    }

    @Test func loadingShowsTheHeaderTheFollowButtonStatisticsAndActivities() async {
        let athletes = repository(status: .none)
        let store = makeStore(athletes)

        await store.load()
        await store.load()

        #expect(store.phase == .loaded)
        #expect(store.profile?.athlete.displayName == "Léa Bernard")
        #expect(store.followStatus == FollowStatus.none)
        #expect(store.yearToDateDistance == Distance(meters: 412_000))
        #expect(store.activities.posts.count == 1)
        #expect(athletes.profileCalls == ["lea"])
    }

    @Test func followingAnAthleteWhoApprovesFollowersShowsRequestSentAndATapCancels() async {
        let follows = FakeFollowRepository()
        follows.followResult = .success(.pending)
        let store = makeStore(repository(status: .none), follows)
        await store.load()

        await store.follow()
        #expect(store.followStatus == .pending)
        #expect(store.profile?.followerCount == 10)

        await store.unfollow()
        #expect(store.followStatus == FollowStatus.none)
        #expect(follows.calls == [.follow("lea"), .unfollow("lea")])
    }

    @Test func followingUpdatesTheCounterAndReloadsWhatIsNowVisible() async {
        let athletes = repository(status: .none, followers: 10)
        let store = makeStore(athletes)
        await store.load()

        athletes.profileResult = .success(.lea(status: .accepted, followers: 11, activities: 50))
        await store.follow()

        #expect(store.followStatus == .accepted)
        #expect(store.profile?.followerCount == 11)
        #expect(store.profile?.activityCount == 50)
        #expect(athletes.profileCalls == ["lea", "lea"])
        #expect(athletes.activityCalls.count == 2)
    }

    @Test func unfollowingFromTheMenuResetsTheButtonAndTheCounter() async {
        let athletes = repository(status: .accepted, followers: 11)
        let follows = FakeFollowRepository()
        follows.followerCount = 10
        let store = makeStore(athletes, follows)
        await store.load()

        athletes.profileResult = .failure(.network)
        await store.unfollow()

        #expect(store.followStatus == FollowStatus.none)
        #expect(store.profile?.followerCount == 10)
    }

    @Test func aFailedFollowRollsBackWithAToast() async {
        let follows = FakeFollowRepository()
        follows.followResult = .failure(.network)
        let store = makeStore(repository(status: .none), follows)
        await store.load()

        await store.follow()

        #expect(store.followStatus == FollowStatus.none)
        #expect(store.profile?.followerCount == 10)
        #expect(store.follows.toast == "L'abonnement n'a pas abouti, réessayez.")
    }

    @Test func aFailedLoadSaysSoAndCanBeRetried() async {
        let athletes = FakeAthleteRepository()
        athletes.profileResult = .failure(.notFound)
        let store = makeStore(athletes)

        await store.load()
        #expect(store.phase == .failed(message: "Ce profil n'est plus disponible."))

        athletes.profileResult = .success(.lea(status: .none))
        await store.refresh()
        #expect(store.phase == .loaded)
    }
}

private extension AthleteProfile {
    static func lea(status: FollowStatus, followers: Int = 10, activities: Int = 42) -> AthleteProfile {
        .fixture(
            id: "lea",
            displayName: "Léa Bernard",
            activityCount: activities,
            followerCount: followers,
            viewerFollowStatus: status,
            approveFollowers: nil,
            itineraryCount: nil
        )
    }
}
