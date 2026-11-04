import Foundation
import UIKit
import Testing
@testable import StravaClone

@MainActor
struct ProfileStoreTests {
    private func makeStore(
        _ athletes: FakeAthleteRepository = FakeAthleteRepository(),
        _ profiles: FakeProfileRepository = FakeProfileRepository(),
        progress: FakeProgressRepository = FakeProgressRepository(),
        avatars: FakeAvatarRepository = FakeAvatarRepository(),
        gallery: FakeAthleteGalleryRepository = FakeAthleteGalleryRepository(),
        analytics: FakeAnalyticsClient = FakeAnalyticsClient()
    ) -> ProfileStore {
        ProfileStore(
            loadProfile: LoadProfile(repository: athletes),
            loadYearToDateDistance: LoadYearToDateDistance(repository: FakeAthleteStatsRepository.allSports()),
            loadEditableProfile: LoadEditableProfile(repository: profiles),
            updateProfile: UpdateProfile(repository: profiles),
            setApproveFollowers: SetApproveFollowers(repository: profiles),
            activities: ProfileActivitiesStore(loadActivities: LoadProfileActivities(repository: athletes)),
            progress: ProfileProgressStore(loadProgress: LoadProgress(repository: progress)),
            gallery: AthleteGalleryStore(
                loadGallery: LoadAthleteGallery(repository: gallery),
                message: ProfileMessages.message(for:),
                analytics: analytics
            ),
            avatar: AvatarEditor(
                repository: avatars,
                analytics: FakeAnalyticsClient(),
                imageLoader: ImageLoader(cache: URLCache(memoryCapacity: 10_000_000, diskCapacity: 0)),
                isOnline: { true }
            )
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

    @Test func openingGalerieLoadsMyMediaAndPullToRefreshReloadsThem() async {
        let gallery = FakeAthleteGalleryRepository()
        gallery.pages[nil] = .success(GalleryPage(items: [.fixture()], nextCursor: nil))
        let analytics = FakeAnalyticsClient()
        let store = makeStore(loadedRepository(), gallery: gallery, analytics: analytics)
        await store.load(athleteId: "me")
        #expect(gallery.calls.isEmpty)

        await store.openGallery()
        await store.refresh()

        #expect(store.gallery.items.count == 1)
        #expect(gallery.calls.map(\.athleteId) == ["me", "me"])
        #expect(analytics.events == [.galleryViewed(isOwn: true)])
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

    @Test func savingUpdatesTheHeaderAndPutsTheMainSportFirst() async throws {
        let profiles = FakeProfileRepository()
        let athletes = loadedRepository()
        let store = makeStore(athletes, profiles)
        await store.load(athleteId: "me")
        var edited = EditableProfile(firstName: " Léa ", lastName: "Bernard", bio: " Grimpeuse ", countryCode: "FR")
        edited.mainSport = .ride

        let error = await store.save(edited)

        #expect(error == nil)
        #expect(store.profile?.athlete.displayName == "Léa Bernard")
        #expect(store.profile?.practicedSports == [.ride, .run])
        let update = try #require(profiles.updates.first)
        #expect(update.name == ProfileName(firstName: "Léa", lastName: "Bernard"))
        #expect(update.bio == "Grimpeuse")
        #expect(update.countryCode == "FR")
    }

    @Test func aRefusedSaveKeepsTheHeaderAndSaysWhy() async {
        let profiles = FakeProfileRepository()
        profiles.updateResult = .failure(.network)
        let store = makeStore(loadedRepository(), profiles)
        await store.load(athleteId: "me")

        let error = await store.save(EditableProfile(firstName: "Léa", lastName: "Bernard"))

        #expect(error == "Une erreur est survenue, réessayez.")
        #expect(store.profile?.athlete.displayName == "Camille Martin")
    }

    @Test func theSheetStartsFromMyEditableProfile() async {
        let profiles = FakeProfileRepository()
        profiles.editableResult = .success(EditableProfile(firstName: "Léa", lastName: "Bernard", weightKg: 59))
        let store = makeStore(loadedRepository(), profiles)

        #expect(await store.editableProfile() == .success(EditableProfile(firstName: "Léa", lastName: "Bernard", weightKg: 59)))

        profiles.editableResult = .failure(.offline)
        #expect(await store.editableProfile() == .failure(EditProfileFailure(message: "Vous êtes hors ligne.")))
    }

    @Test func myNewPhotoShowsInTheHeaderOnceStored() async throws {
        let store = makeStore(loadedRepository())
        await store.load(athleteId: "me")
        let photo = try #require(AvatarSourceImage(uiImage: UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { _ in }))

        let stored = await store.avatar.send(photo, cropping: CGRect(x: 0, y: 0, width: 40, height: 40), source: .library, entry: .profile)

        #expect(stored)
        #expect(store.profile?.athlete.avatarURL == URL(string: "https://bucket.test/avatars/me/new.jpg?X-Amz-Signature=a"))
        #expect(store.profile?.athlete.displayName == "Camille Martin")
    }

    @Test func removingMyPhotoBringsBackMyInitials() async {
        let athletes = loadedRepository()
        athletes.profileResult = .success(.fixture(avatarURL: URL(string: "https://bucket.test/avatars/me/old.jpg")))
        let store = makeStore(athletes)
        await store.load(athleteId: "me")

        await store.avatar.remove(entry: .editProfile)

        #expect(store.profile?.athlete.avatarURL == nil)
    }

    @Test func anInvalidNameIsNotSent() async {
        let profiles = FakeProfileRepository()
        let store = makeStore(loadedRepository(), profiles)
        await store.load(athleteId: "me")

        let error = await store.save(EditableProfile(firstName: "  ", lastName: "Bernard"))

        #expect(error == "Prénom et nom : de 1 à 50 caractères chacun.")
        #expect(profiles.updates.isEmpty)
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
