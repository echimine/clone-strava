import Testing
@testable import StravaClone

@MainActor
struct LocationBroadcasterTests {
    @Test func fansOutToEverySubscriber() async {
        let broadcaster = LocationBroadcaster<Int> { _ in }
        var first = broadcaster.subscribe().makeAsyncIterator()
        var second = broadcaster.subscribe().makeAsyncIterator()

        broadcaster.send(1)

        #expect(await first.next() == 1)
        #expect(await second.next() == 1)
    }

    @Test func replaysLatestValueToNewSubscriber() async {
        let broadcaster = LocationBroadcaster<Int> { _ in }
        let keepAlive = broadcaster.subscribe()
        broadcaster.send(1)
        broadcaster.send(2)

        var late = broadcaster.subscribe().makeAsyncIterator()

        #expect(await late.next() == 2)
        _ = keepAlive
    }

    /// ADR-031 §3: the Recording's stream never replays a stale position.
    @Test func liveSubscriberGetsNoReplay() async {
        let broadcaster = LocationBroadcaster<Int> { _ in }
        let keepAlive = broadcaster.subscribe()
        broadcaster.send(1)

        var live = broadcaster.subscribe(replaysLatest: false, bufferingPolicy: .unbounded).makeAsyncIterator()
        broadcaster.send(2)

        #expect(await live.next() == 2)
        _ = keepAlive
    }

    /// ADR-031 §3: no sample dropped silently while the Recording is busy writing.
    @Test func unboundedSubscriberKeepsEverySample() async {
        let broadcaster = LocationBroadcaster<Int> { _ in }
        var live = broadcaster.subscribe(replaysLatest: false, bufferingPolicy: .unbounded).makeAsyncIterator()

        for value in 1...100 {
            broadcaster.send(value)
        }

        var received: [Int] = []
        for _ in 1...100 {
            if let value = await live.next() { received.append(value) }
        }
        #expect(received == Array(1...100))
    }

    @Test func reportsActivityOnFirstAndLastSubscriber() async {
        var changes: [Bool] = []
        let broadcaster = LocationBroadcaster<Int> { changes.append($0) }

        let consumers = (0..<2).map { _ in
            let stream = broadcaster.subscribe()
            return Task { for await _ in stream {} }
        }
        #expect(changes == [true])

        for consumer in consumers {
            consumer.cancel()
        }
        while broadcaster.subscriberCount > 0 {
            await Task.yield()
        }

        #expect(changes == [true, false])
    }
}
