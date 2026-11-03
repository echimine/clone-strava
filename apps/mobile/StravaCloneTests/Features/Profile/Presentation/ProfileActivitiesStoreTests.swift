import Foundation
import Testing
@testable import StravaClone

@MainActor
struct ProfileActivitiesStoreTests {
    private func makeStore(_ athletes: FakeAthleteRepository, changes: ActivityChanges? = nil) -> ProfileActivitiesStore {
        ProfileActivitiesStore(loadActivities: LoadProfileActivities(repository: athletes), activityChanges: changes)
    }

    @Test func showsTheAthletesActivitiesAndPagesWithoutDuplicates() async {
        let athletes = FakeAthleteRepository()
        let first = (0..<5).map { _ in ActivityPost.fixture(viewerIsAuthor: true) }
        let extra = ActivityPost.fixture(viewerIsAuthor: true)
        athletes.pages[nil] = .success(FeedPage(posts: first, nextCursor: "c1"))
        athletes.pages["c1"] = .success(FeedPage(posts: [first[4], extra], nextCursor: nil))
        let store = makeStore(athletes)

        await store.refresh(athleteId: "me")
        await store.loadMoreIfNeeded(currentPost: first[0])
        #expect(athletes.activityCalls.count == 1)

        await store.loadMoreIfNeeded(currentPost: first[4])
        await store.loadMoreIfNeeded(currentPost: extra)

        #expect(store.posts == first + [extra])
        #expect(athletes.activityCalls.map(\.cursor) == [nil, "c1"])
        #expect(athletes.activityCalls.allSatisfy { $0.athleteId == "me" })
    }

    @Test func anEmptyListAndAFailureAreDistinct() async {
        let athletes = FakeAthleteRepository()
        athletes.pages[nil] = .success(FeedPage(posts: [], nextCursor: nil))
        let store = makeStore(athletes)
        await store.refresh(athleteId: "me")
        #expect(store.isEmpty)

        let failing = makeStore(FakeAthleteRepository())
        await failing.refresh(athleteId: "me")
        #expect(failing.phase == .failed(message: "Une erreur est survenue, réessayez."))
        #expect(!failing.isEmpty)
    }

    @Test func followsWhatTheDetailChanges() async {
        let athletes = FakeAthleteRepository()
        let kept = ActivityPost.fixture(viewerIsAuthor: true)
        let deleted = ActivityPost.fixture(viewerIsAuthor: true)
        athletes.pages[nil] = .success(FeedPage(posts: [kept, deleted], nextCursor: nil))
        let changes = ActivityChanges()
        let store = makeStore(athletes, changes: changes)
        await store.refresh(athleteId: "me")

        changes.publish(.updated(.fixture(id: kept.id, title: "Nouveau titre", viewerIsAuthor: true)))
        changes.publish(.deleted(deleted.id))

        #expect(await eventually { store.posts.map(\.title) == ["Nouveau titre"] })
    }

    @Test func resetForgetsTheList() async {
        let athletes = FakeAthleteRepository()
        athletes.pages[nil] = .success(FeedPage(posts: [.fixture()], nextCursor: "c1"))
        let store = makeStore(athletes)
        await store.refresh(athleteId: "me")

        store.reset()

        #expect(store.posts.isEmpty)
        #expect(store.phase == .idle)
    }
}
