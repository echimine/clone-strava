import Foundation
import Testing
@testable import StravaClone

/// Topic subscriptions shared by the screens of the shared connection (ADR-034 §5, ADR-036 §8):
/// the gateway keeps one subscription per topic, so the first holder subscribes and the last
/// one unsubscribes.
struct RealtimeTopicSubscriptionsTests {
    private let topic = "activity:7c9e6679-7425-40de-944b-e07fc1f90ae7"

    private func sub(_ grant: String) -> String {
        #"{"a":"sub","grant":"\#(grant)","topic":"\#(topic)"}"#
    }

    private var unsub: String { #"{"a":"unsub","topic":"\#(topic)"}"# }

    /// Detail open, Kudos and comments pushed over it, then the detail stops listening: the
    /// screen on top keeps the subscription until it closes too.
    @Test func onlyTheFirstHolderSubscribesAndOnlyTheLastUnsubscribes() async {
        let channel = FakeRealtimeChannel()
        let subscriptions = RealtimeTopicSubscriptions(channel: channel, grant: FakeRealtimeGrants().grant)

        await subscriptions.acquire(topic)
        await subscriptions.acquire(topic)
        await subscriptions.release(topic)

        #expect(channel.sent == [sub("grant-1")])

        await subscriptions.release(topic)

        #expect(channel.sent == [sub("grant-1"), unsub])
    }

    /// A screen that closes before its grant arrives: the late `sub` is not sent.
    @Test func aSubscriptionReleasedWhileItsGrantIsPendingIsNotSent() async {
        let channel = FakeRealtimeChannel()
        let gate = AsyncStream<Void>.makeStream()
        let subscriptions = RealtimeTopicSubscriptions(channel: channel) { _ in
            for await _ in gate.stream { break }
            return "late-grant"
        }

        let opening = Task { await subscriptions.acquire(topic) }
        #expect(await eventually { await subscriptions.holders(of: topic) == 1 })
        await subscriptions.release(topic)
        gate.continuation.yield()
        await opening.value

        #expect(channel.sent == [unsub])
    }

    /// After a reconnection only topics still held are subscribed again.
    @Test func resubscribesOnlyTopicsStillHeld() async {
        let channel = FakeRealtimeChannel()
        let subscriptions = RealtimeTopicSubscriptions(channel: channel, grant: FakeRealtimeGrants().grant)
        await subscriptions.acquire(topic)
        await subscriptions.release(topic)

        await subscriptions.resubscribe(topic)

        #expect(channel.sent == [sub("grant-1"), unsub])
    }

    /// A release without a matching acquire changes nothing.
    @Test func anUnmatchedReleaseSendsNothing() async {
        let channel = FakeRealtimeChannel()
        let subscriptions = RealtimeTopicSubscriptions(channel: channel, grant: FakeRealtimeGrants().grant)

        await subscriptions.release(topic)

        #expect(channel.sent.isEmpty)
    }
}
