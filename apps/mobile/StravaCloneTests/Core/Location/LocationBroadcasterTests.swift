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
