import Foundation
import Testing
@testable import StravaClone

/// The detail's subscription to `activity:{id}` (ADR-034 §5) on the shared connection: a grant
/// then `sub` on opening, again after each reconnection, `unsub` on closing.
@MainActor
struct RealtimeActivityLiveEventSourceTests {
    private let id = ActivityID(UUID(uuidString: "7C9E6679-7425-40DE-944B-E07FC1F90AE7")!)
    private let topic = "activity:7c9e6679-7425-40de-944b-e07fc1f90ae7"

    private func sub(_ grant: String) -> String {
        #"{"a":"sub","grant":"\#(grant)","topic":"\#(topic)"}"#
    }

    private var unsub: String { #"{"a":"unsub","topic":"\#(topic)"}"# }

    @Test func subscribesWithAGrantOnOpeningAndUnsubscribesOnClosing() async {
        let channel = FakeRealtimeChannel()
        let grants = FakeRealtimeGrants()
        let source = RealtimeActivityLiveEventSource(channel: channel, grant: grants.grant)

        let detail = Task { for await _ in source.events(of: id) {} }

        #expect(await eventually { channel.sent == [sub("grant-1")] })
        #expect(grants.topics == [topic])

        detail.cancel()
        #expect(await eventually { channel.sent == [sub("grant-1"), unsub] })
    }

    /// The gateway forgets a connection's topics: each reconnection asks a fresh grant, then
    /// tells the detail to catch up (ADR-034 §5.4).
    @Test func resubscribesWithAFreshGrantAfterAReconnectionThenAsksForACatchUp() async {
        let channel = FakeRealtimeChannel()
        let grants = FakeRealtimeGrants()
        let source = RealtimeActivityLiveEventSource(channel: channel, grant: grants.grant)
        let received = Locked<[ActivityLiveEvent]>([])
        let detail = Task { for await event in source.events(of: id) { received.value.append(event) } }
        #expect(await eventually { channel.sent == [sub("grant-1")] })

        channel.reconnect()

        #expect(await eventually { received.value == [.reconnected] })
        #expect(channel.sent == [sub("grant-1"), sub("grant-2")])
        #expect(grants.topics == [topic, topic])
        detail.cancel()
    }

    /// Opened while disconnected: the subscription waits for the connection.
    @Test func subscribesOnTheNextConnectionWhenOpenedOffline() async {
        let channel = FakeRealtimeChannel()
        channel.isConnected = false
        let source = RealtimeActivityLiveEventSource(channel: channel, grant: FakeRealtimeGrants().grant)
        let detail = Task { for await _ in source.events(of: id) {} }
        #expect(await eventually { channel.attempts == 1 })
        #expect(channel.sent.isEmpty)

        channel.reconnect()

        #expect(await eventually { channel.sent == [sub("grant-2")] })
        detail.cancel()
    }

    /// The connection also carries the `user:` topic: only this Activity's comment and kudos
    /// events reach the live updates, whatever the case of the ids. `activity.updated` /
    /// `activity.deleted` are the detail store's own (`ActivityEventSource`, ADR-033 §8): this
    /// subscription only brings them onto the connection.
    @Test func translatesThisActivitysCommentAndKudosEventsOnly() async {
        let channel = FakeRealtimeChannel()
        let source = RealtimeActivityLiveEventSource(channel: channel, grant: FakeRealtimeGrants().grant)
        let received = Locked<[ActivityLiveEvent]>([])
        let detail = Task { for await event in source.events(of: id) { received.value.append(event) } }
        #expect(await eventually { channel.sent.count == 1 })
        let comment = UUID(uuidString: "0B5A5C1E-1F4E-4C55-9D6E-0D3F8F6E2A11")!
        let mine = "7c9e6679-7425-40de-944b-e07fc1f90ae7"
        let other = "1c6b6d2f-2a5f-4d66-8e7f-1e4a9a7f3b22"

        channel.push(type: "comment.created", data: ["activityId": mine, "commentId": "0b5a5c1e-1f4e-4c55-9d6e-0d3f8f6e2a11"])
        channel.push(type: "comment.created", data: ["activityId": other, "commentId": "0b5a5c1e-1f4e-4c55-9d6e-0d3f8f6e2a11"])
        channel.push(type: "comment.updated", data: ["activityId": mine, "commentId": "0b5a5c1e-1f4e-4c55-9d6e-0d3f8f6e2a11"])
        channel.push(type: "activity.updated", data: ["activityId": mine])
        channel.push(type: "comment.deleted", data: ["activityId": mine, "commentId": "0b5a5c1e-1f4e-4c55-9d6e-0d3f8f6e2a11"])
        channel.push(type: "activity.processed", data: ["activityId": mine, "status": "processed"])
        channel.push(type: "kudos.changed", data: ["activityId": other])
        channel.push(type: "kudos.changed", data: ["activityId": mine.uppercased()])

        #expect(await eventually { received.value.count == 4 })
        #expect(received.value == [
            .commentCreated(comment),
            .commentUpdated(comment),
            .commentDeleted(comment),
            .kudosChanged,
        ])
        detail.cancel()
    }

    /// `activity.deleted` (ADR-034 §5): the store shows the unavailable state, the
    /// subscription ends.
    @Test func unsubscribesOnceTheActivityIsDeleted() async {
        let channel = FakeRealtimeChannel()
        let source = RealtimeActivityLiveEventSource(channel: channel, grant: FakeRealtimeGrants().grant)
        let ended = Locked(false)
        let detail = Task {
            for await _ in source.events(of: id) {}
            ended.value = true
        }
        #expect(await eventually { channel.sent == [sub("grant-1")] })

        channel.push(type: "activity.deleted", data: ["activityId": "1c6b6d2f-2a5f-4d66-8e7f-1e4a9a7f3b22"])
        channel.push(type: "activity.deleted", data: ["activityId": "7c9e6679-7425-40de-944b-e07fc1f90ae7"])

        #expect(await eventually { ended.value })
        #expect(await eventually { channel.sent == [sub("grant-1"), unsub] })
        detail.cancel()
    }
}
