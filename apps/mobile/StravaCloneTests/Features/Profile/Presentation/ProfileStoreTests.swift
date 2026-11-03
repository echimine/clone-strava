import Foundation
import Testing
@testable import StravaClone

@MainActor
struct ProfileStoreTests {
    private func makeStore(
        _ athletes: FakeAthleteRepository = FakeAthleteRepository(),
        _ profiles: FakeProfileRepository = FakeProfileRepository(),
        progress: FakeProgressRepository = FakeProgressRepository()
    ) -> ProfileStore {
        ProfileStore(
            loadProfile: LoadProfile(repository: athletes),
            loadYearToDateDistance: LoadYearToDateDistance(repository: FakeAthleteStatsRepository.allSports()),
            renameAthlete: RenameAthlete(repository: profiles),
            setApproveFollowers: SetApproveFollowers(repository: profiles),
            activities: ProfileActivitiesStore(loadActivities: LoadProfileActivities(repository: athletes)),
            progress: ProfileProgressStore(loadProgress: LoadProgress(repository: progress))
        )
    }

    private func loadedRepository(approveFollowers: Bool = false) -> FakeAthleteRepository {
        let athletes = FakeAthleteRepository()
        athletes.profileResult = .success(.fixture(approveFollowers: approveFollowers))
        athletes.pages[nil] = .success(FeedPage(posts: [.fixture(viewerIsAuthor: true)], nextCursor: nil))
        return athletes
    }

    @Test func loadingShowsMyHeaderStatisticsAndActivities() async {
        let athletes = loadedRepository()
        let store = makeStore(athletes)

        await store.load(athleteId: "me")
        await store.load(athleteId: "me")

        #expect(store.phase == .loaded)
        #expect(store.profile == .fixture())
        #expect(store.yearToDateDistance == Distance(meters: 412_000))
        #expect(store.activities.posts.count == 1)
        #expect(athletes.profileCalls == ["me"])
    }

    @Test func aFailedLoadSaysSoAndCanBeRetried() async {
        let athletes = FakeAthleteRepository()
        athletes.profileResult = .failure(.offline)
        let store = makeStore(athletes)

        await store.load(athleteId: "me")
        #expect(store.phase == .failed(message: "Vous êtes hors ligne."))

        athletes.profileResult = .success(.fixture())
        await store.refresh()
        #expect(store.phase == .loaded)
    }

    @Test func renamingUpdatesTheHeader() async {
        let profiles = FakeProfileRepository()
        let store = makeStore(loadedRepository(), profiles)
        await store.load(athleteId: "me")

        let error = await store.rename(firstName: " Léa ", lastName: "Bernard")

        #expect(error == nil)
        #expect(store.profile?.athlete.displayName == "Léa Bernard")
        #expect(profiles.renames == [ProfileName(firstName: "Léa", lastName: "Bernard")])
    }

    @Test func aRefusedRenameKeepsTheHeaderAndSaysWhy() async {
        let profiles = FakeProfileRepository()
        profiles.renameResult = .failure(.network)
        let store = makeStore(loadedRepository(), profiles)
        await store.load(athleteId: "me")

        let error = await store.rename(firstName: "Léa", lastName: "Bernard")

        #expect(error == "Une erreur est survenue, réessayez.")
        #expect(store.profile?.athlete.displayName == "Camille Martin")
    }

    @Test func anInvalidNameIsNotSent() async {
        let profiles = FakeProfileRepository()
        let store = makeStore(loadedRepository(), profiles)
        await store.load(athleteId: "me")

        let error = await store.rename(firstName: "  ", lastName: "Bernard")

        #expect(error == "Prénom et nom : de 1 à 50 caractères chacun.")
        #expect(profiles.renames.isEmpty)
    }

    @Test func approvingFollowersShowsAtOnceThenTakesTheServersValue() async {
        let profiles = FakeProfileRepository()
        let (gate, open) = AsyncStream<Void>.makeStream()
        profiles.approveGate = gate
        let store = makeStore(loadedRepository(approveFollowers: false), profiles)
        await store.load(athleteId: "me")
        #expect(store.approveFollowers == false)

        let toggle = Task { await store.setApproveFollowers(true) }
        while profiles.approveCalls.isEmpty { await Task.yield() }
        #expect(store.approveFollowers == true)

        open.yield()
        await toggle.value
        #expect(store.approveFollowers == true)
        #expect(store.toast == nil)
        #expect(profiles.approveCalls == [true])
    }

    @Test func aRefusedApprovalSettingRollsBackWithAToast() async {
        let profiles = FakeProfileRepository()
        profiles.approveResult = .failure(.network)
        let store = makeStore(loadedRepository(approveFollowers: true), profiles)
        await store.load(athleteId: "me")

        await store.setApproveFollowers(false)

        #expect(store.approveFollowers == true)
        #expect(store.toast == "Le réglage n'a pas pu être modifié, réessayez.")
    }

    @Test func navigationPushesTheScreensOfTheProfileStack() async {
        let store = makeStore(loadedRepository())
        await store.load(athleteId: "me")
        let id = store.activities.posts[0].id

        store.openSettings()
        store.openActivity(id)
        store.openComments(id)

        #expect(store.path.count == 3)
    }

    @Test func myCountersOpenMyListsAndTheMagnifierTheSearch() async {
        let athletes = FakeAthleteRepository()
        athletes.profileResult = .success(.fixture(followerCount: 12, followingCount: 8, pendingFollowRequestCount: 2))
        let store = makeStore(athletes)
        store.openFollows(.followers)
        #expect(store.path.isEmpty)

        await store.load(athleteId: "me")
        store.openFollows(.following)
        store.openSearch()

        #expect(store.followsRequest(.following)?.list == .following)
        #expect(store.followsRequest(.following)?.isOwn == true)
        #expect(store.followsRequest(.following)?.pendingRequestCount == 2)
        #expect(store.path.count == 2)
    }

    @Test func myCountersFollowWhatMyFollowScreensChange() async {
        let athletes = FakeAthleteRepository()
        athletes.profileResult = .success(.fixture(followerCount: 12, followingCount: 8, pendingFollowRequestCount: 2))
        let store = makeStore(athletes)
        await store.load(athleteId: "me")

        store.apply(FollowCountsChange(followers: 1, pendingRequests: -1))
        store.apply(FollowCountsChange.following(from: FollowStatus.none, to: .accepted))

        #expect(store.profile?.followerCount == 13)
        #expect(store.profile?.followingCount == 9)
        #expect(store.profile?.pendingFollowRequestCount == 1)
    }

    @Test func theStatisticsRowOpensMyStatisticsWithMySports() async {
        let store = makeStore(loadedRepository())
        store.openStatistics()
        #expect(store.path.isEmpty)

        await store.load(athleteId: "me")
        store.openStatistics()

        #expect(store.statisticsRequest == AthleteStatisticsRequest(athleteId: "me", sports: [.run]))
        #expect(store.path.count == 1)
    }

    @Test func pullToRefreshReloadsTheProgressOnceShown() async {
        let progress = FakeProgressRepository()
        progress.results[.run] = .success(.fixture(sport: .run))
        let store = makeStore(loadedRepository(), progress: progress)
        await store.load(athleteId: "me")
        #expect(progress.calls.isEmpty)

        await store.progress.load(practicedSports: [.run])
        await store.refresh()

        #expect(progress.calls == [.run, .run])
    }

    @Test func signingOutForgetsTheProfile() async {
        let athletes = loadedRepository()
        let store = makeStore(athletes)
        await store.load(athleteId: "me")
        store.openSettings()
        store.tab = .more

        store.reset()

        #expect(store.profile == nil)
        #expect(store.phase == .idle)
        #expect(store.yearToDateDistance == nil)
        #expect(store.path.isEmpty)
        #expect(store.tab == .activities)
        #expect(store.activities.posts.isEmpty)
        #expect(store.progress.phase == .idle)

        await store.load(athleteId: "other")
        #expect(athletes.profileCalls == ["me", "other"])
    }
}
