import Foundation
import Testing
@testable import StravaClone

@MainActor
struct AthleteActivitiesStoreTests {
    private func makeStore(
        _ athletes: FakeAthleteRepository,
        kudos: FakeAthleteKudosRepository = FakeAthleteKudosRepository(),
        changes: ActivityChanges? = nil
    ) -> AthleteActivitiesStore {
        AthleteActivitiesStore(
            loadActivities: LoadAthleteActivities(repository: athletes),
            setKudos: SetAthleteActivityKudos(repository: kudos),
            activityChanges: changes
        )
    }

    @Test func showsTheAthletesActivitiesAndPagesWithoutDuplicates() async {
        let athletes = FakeAthleteRepository()
        let first = (0..<5).map { _ in ActivityPost.fixture() }
        let extra = ActivityPost.fixture()
        athletes.pages[nil] = .success(FeedPage(posts: first, nextCursor: "c1"))
        athletes.pages["c1"] = .success(FeedPage(posts: [first[4], extra], nextCursor: nil))
        let store = makeStore(athletes)

        await store.refresh(athleteId: "lea")
        await store.loadMoreIfNeeded(currentPost: first[4])
        await store.loadMoreIfNeeded(currentPost: extra)

        #expect(store.posts == first + [extra])
        #expect(athletes.activityCalls.map(\.cursor) == [nil, "c1"])
        #expect(athletes.activityCalls.allSatisfy { $0.athleteId == "lea" })
    }

    @Test func kudosShowAtOnceTakeTheServersCountAndReachTheFeed() async {
        let athletes = FakeAthleteRepository()
        let post = ActivityPost.fixture(kudos: 2)
        athletes.pages[nil] = .success(FeedPage(posts: [post], nextCursor: nil))
        let kudos = FakeAthleteKudosRepository()
        kudos.kudosCount = 5
        let changes = ActivityChanges()
        let feed = changes.subscribe()
        let store = makeStore(athletes, kudos: kudos, changes: changes)
        await store.refresh(athleteId: "lea")

        await store.toggleKudos(on: post.id)

        let expected = ActivityEngagement(kudosCount: 5, commentCount: 0, viewerHasKudoed: true)
        #expect(store.posts[0].engagement == expected)
        #expect(kudos.calls.map(\.given) == [true])
        #expect(await changes.published(on: feed) == [.engagement(post.id, expected)])
    }

    @Test func aFailedKudosRollsBackWithANotice() async {
        let athletes = FakeAthleteRepository()
        let post = ActivityPost.fixture(kudos: 2)
        athletes.pages[nil] = .success(FeedPage(posts: [post], nextCursor: nil))
        let kudos = FakeAthleteKudosRepository()
        kudos.failure = .network
        let store = makeStore(athletes, kudos: kudos)
        await store.refresh(athleteId: "lea")

        await store.toggleKudos(on: post.id)

        #expect(store.posts[0].engagement == post.engagement)
        #expect(store.notice == "Le kudos n'a pas pu être envoyé, réessayez.")
    }

    @Test func followsWhatTheDetailChanges() async {
        let athletes = FakeAthleteRepository()
        let kept = ActivityPost.fixture()
        let deleted = ActivityPost.fixture()
        athletes.pages[nil] = .success(FeedPage(posts: [kept, deleted], nextCursor: nil))
        let changes = ActivityChanges()
        let store = makeStore(athletes, changes: changes)
        await store.refresh(athleteId: "lea")

        changes.publish(.updated(.fixture(id: kept.id, title: "Nouveau titre")))
        changes.publish(.deleted(deleted.id))

        #expect(await eventually { store.posts.map(\.title) == ["Nouveau titre"] })
    }
}
