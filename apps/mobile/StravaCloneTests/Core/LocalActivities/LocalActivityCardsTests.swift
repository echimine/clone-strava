import Foundation
import Testing
@testable import StravaClone

/// The feed cards of local Activities (ADR-031 §14): provisional values, a route from the local
/// points and a status line that follows the sending, in the serialized suite of
/// `ActivitySenderTests` (shared network stub).
extension ActivitySenderTests {
    private func statuses(_ harness: ActivitySenderHarness) async throws -> [LocalActivityStatus] {
        try await harness.store.cards().map(\.status)
    }

    @Test func aCardShowsTheProvisionalValuesAndARouteFromTheLocalPoints() async throws {
        let harness = try ActivitySenderHarness()
        try await harness.saveRecordedActivity()

        let card = try #require(try await harness.store.cards().first)

        #expect(card.id == harness.id)
        #expect(card.activity.title == "Course à pied le matin")
        #expect(card.activity.sport == .run)
        #expect(card.activity.distance == Distance(meters: 1_500))
        #expect(card.activity.movingTimeS == 540)
        #expect(card.route?.precision == 5)
        #expect(card.route?.decode().count == 3)
    }

    @Test func anActivitySavedOfflineWalksThroughEachStatusLine() async throws {
        let harness = try ActivitySenderHarness()
        try await harness.saveRecordedActivity()
        let sender = harness.makeSender()
        #expect(try await statuses(harness) == [.sending])

        ActivitySenderHarness.route { _ in .offline }
        await sender.send()
        #expect(try await statuses(harness) == [.waitingForNetwork])

        ActivitySenderHarness.route { _ in .status(503) }
        await sender.send(ignoringBackoff: true)
        #expect(try await statuses(harness) == [.retryingSoon])

        ActivitySenderHarness.route { step in
            switch step {
            case "create": harness.created()
            case "upload": .status(200)
            default: harness.completed()
            }
        }
        await sender.send(ignoringBackoff: true)
        #expect(try await statuses(harness) == [.processing])

        // Processed: the feed reloads and the card is wiped.
        ActivitySenderHarness.route { _ in harness.detail("processed") }
        try await harness.store.wipe(await sender.trackProcessing())
        #expect(try await harness.store.cards().isEmpty)
    }

    @Test func aRefusedActivityShowsTheFailureWithItsReason() async throws {
        let harness = try ActivitySenderHarness()
        try await harness.saveRecordedActivity()
        ActivitySenderHarness.route { _ in ActivitySenderHarness.refused(422, "validation_error") }

        await harness.makeSender().send()

        #expect(try await statuses(harness) == [.failed(reason: "validation_error")])
    }

    @Test func cardsAreNewestFirstAndADeletedOneDisappearsAtOnce() async throws {
        let older = try ActivitySenderHarness()
        try await older.saveRecordedActivity()
        let newer = try ActivitySenderHarness(database: older.database)
        try await newer.saveRecordedActivity(startingAt: ActivitySenderHarness.start.addingTimeInterval(1_800))
        ActivitySenderHarness.route { step in step == "create" ? older.created() : .offline }
        let sender = older.makeSender()
        await sender.send()
        #expect(try await older.store.cards().map(\.id) == [newer.id, older.id])

        // Known to the server: a `delete_activity` stays queued (offline), the card is gone.
        try await sender.delete(older.id)

        #expect(try await older.store.cards().map(\.id) == [newer.id])
    }

    @Test func theCardsAreObservedAsTheQueueMoves() async throws {
        let harness = try ActivitySenderHarness()
        try await harness.saveRecordedActivity()
        var iterator = harness.store.observeCards().makeAsyncIterator()
        #expect(await iterator.next()?.map(\.status) == [.sending])

        ActivitySenderHarness.route { _ in .offline }
        await harness.makeSender().send()

        #expect(await iterator.next()?.map(\.status) == [.waitingForNetwork])
    }
}
