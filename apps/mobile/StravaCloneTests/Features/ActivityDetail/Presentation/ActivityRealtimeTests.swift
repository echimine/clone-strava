import Foundation
import Testing
@testable import StravaClone

/// `activity.updated` on the owner's topic (ADR-033 §8): the feed reloads that card and an open
/// detail reloads, e.g. when the official values land after a sport change (§5).
@MainActor
struct ActivityRealtimeTests {
    private let before = ActivityDetail.fixture(sport: .ride, stats: .fixture(distanceM: 6_000))
    private var reprocessed: ActivityDetail {
        var detail = before
        detail.stats = .fixture(distanceM: 8_000)
        return detail
    }

    @Test func anOpenDetailReloadsOnItsActivityUpdatedEvent() async {
        let repository = FakeActivityDetailRepository(.success(before), .success(reprocessed))
        let events = FakeActivityEventSource()
        let store = ActivityDetailStore(
            id: before.id,
            loadDetail: LoadActivityDetail(repository: repository),
            updateActivity: UpdateActivity(repository: repository),
            changes: ActivityChanges(),
            events: events
        )
        await store.load()
        let observation = Task { await store.observeEvents() }
        defer { observation.cancel() }
        #expect(await eventually { events.subscriberCount == 1 })

        // Another Activity's event: nothing to reload.
        events.send(.updated(ActivityID()))
        events.send(.updated(before.id))

        #expect(await eventually { store.detail == reprocessed })
        #expect(repository.requestedIds == [before.id, before.id])
    }

    @Test func theFeedCardReloadsOnAnActivityUpdatedEvent() async {
        let changes = ActivityChanges()
        let feedRepository = FakeFeedRepository()
        feedRepository.pages[nil] = .success(FeedPage(posts: [before.post], nextCursor: nil))
        let feed = FeedStore(
            loadFeed: LoadFeed(repository: feedRepository),
            toggleKudos: ToggleKudos(repository: feedRepository),
            events: FakeFeedEventSource(),
            activityChanges: changes
        )
        await feed.refresh()
        let events = FakeActivityEventSource()
        let reload = ReloadUpdatedActivities(
            loadDetail: LoadActivityDetail(repository: FakeActivityDetailRepository(.success(reprocessed))),
            changes: changes,
            events: events
        )
        let running = Task { await reload.run() }
        defer { running.cancel() }
        #expect(await eventually { events.subscriberCount == 1 })

        events.send(.updated(before.id))

        #expect(await eventually { feed.posts == [reprocessed.post] })
    }

    /// Deleted or no longer visible by then: the card goes.
    @Test func aCardWhoseActivityIsGoneIsRemoved() async {
        let changes = ActivityChanges()
        let published = changes.subscribe()
        let events = FakeActivityEventSource()
        let reload = ReloadUpdatedActivities(
            loadDetail: LoadActivityDetail(repository: FakeActivityDetailRepository(.failure(.notFound))),
            changes: changes,
            events: events
        )
        let running = Task { await reload.run() }
        defer { running.cancel() }
        #expect(await eventually { events.subscriberCount == 1 })

        events.send(.updated(before.id))

        for await change in published {
            #expect(change == .deleted(before.id))
            break
        }
    }
}
